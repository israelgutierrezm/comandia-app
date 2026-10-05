import 'dart:async';
import 'dart:convert';

import 'package:comandia_app/core/providers.dart';
import 'package:comandia_app/features/auth/auth.dart';
import 'package:comandia_app/features/pos/pos.dart';
import 'package:comandia_app/features/reports/reports.dart';
import 'package:comandia_app/features/sessions/sessions.dart';
import 'package:comandia_app/features/supervision/supervision.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);
  final ResponseBody Function(RequestOptions options) handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      handler(options);
}

ResponseBody _json(Object body, int status) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

ResponseBody _empty(int status) => ResponseBody.fromString('', status);

ResponseBody _unauthenticated() =>
    _json({'type': 'unauthenticated', 'title': 'No has iniciado sesión.', 'status': 401}, 401);

/// Una persona del negocio: su rol, su sucursal y sus permisos, tal como los devuelve `/context`.
class _Person {
  const _Person(this.name, this.role, this.branch, this.permissions);
  final String name;
  final String role;
  final String branch;
  final List<String> permissions;

  Map<String, Object?> get context => {
        'tenant': {'name': 'Fonda del Centro'},
        'membership': {'display_name': name},
        'active_role': {'ulid': 'ROLE-$role', 'name': role},
        'active_branch': {'ulid': 'BR-$branch', 'name': branch},
        'branches': [
          {'ulid': 'BR-$branch', 'name': branch},
        ],
        'permissions': permissions,
      };
}

const _ana = _Person('Ana Gómez', 'Gerente', 'Centro', ['pos.accounts.charge', 'pos.sessions.close']);
const _beto = _Person('Beto Ruiz', 'Mesero', 'Roma', ['pos.accounts.view']);
const _byToken = {'tok-ana': _ana, 'tok-beto': _beto};

/// El servidor de prueba responde según QUIÉN opera (el token que viaja). Sin token, o con uno revocado, responde 401
/// como el real.
ResponseBody _server(RequestOptions o, Set<String> revoked) {
  if (o.path == '/auth/token') {
    if (o.method == 'DELETE') return _empty(204);
    final beto = (o.data as Map)['email'] == 'beto@fonda.mx';
    return _json({'token': beto ? 'tok-beto' : 'tok-ana', 'context': <String, dynamic>{}}, 201);
  }

  final token = (o.headers['Authorization'] as String?)?.replaceFirst('Bearer ', '');
  final who = _byToken[token];
  if (who == null || revoked.contains(token)) return _unauthenticated();

  return switch (o.path) {
    '/context' => _json({'data': who.context}, 200),
    '/pos-accounts' => _json({
        'data': [
          {'ulid': 'ACC-${who.role}', 'display_name': 'Mesa de ${who.name}'},
        ],
      }, 200),
    '/pos-sessions' => _json({
        'data': [
          {'ulid': 'S-${who.role}', 'folio': 'Turno de ${who.name}', 'status': 'open'},
        ],
      }, 200),
    '/reports' => _json({
        'data': [
          {'key': 'ventas-${who.role}', 'label': 'Ventas para ${who.role}'},
        ],
      }, 200),
    _ => _json({'data': <String, dynamic>{}}, 200),
  };
}

/// Deja correr la cola hasta que la sesión llegue a [status]; si no llega, el expect lo dice.
Future<void> _until(ProviderContainer c, AuthStatus status) async {
  for (var i = 0; i < 20 && c.read(authControllerProvider) != status; i++) {
    await pumpEventQueue();
  }
  expect(c.read(authControllerProvider), status);
}

/// Mantiene «montadas» las pantallas que muestran [providers] (como una pestaña que los vigila).
List<ProviderSubscription<Object?>> _screens(ProviderContainer c, List<ProviderListenable<Object?>> providers) =>
    [for (final p in providers) c.listen<Object?>(p, (_, _) {})];

final _taco = CatalogArticle(ulid: 'ART1', name: 'Taco', basePrice: '20.00');

void main() {
  // Almacenamiento seguro en memoria; como en un aparato real, la plataforma responde en otro turno del ciclo de eventos.
  final store = <String, String>{};

  setUp(() {
    store.clear();
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        await Future<void>.delayed(Duration.zero);
        final args = (call.arguments as Map?) ?? const {};
        final key = args['key'] as String?;
        switch (call.method) {
          case 'write':
            final value = args['value'] as String?;
            if (key != null) {
              value == null ? store.remove(key) : store[key] = value;
            }
            return null;
          case 'read':
            return key == null ? null : store[key];
          case 'delete':
            if (key != null) store.remove(key);
            return null;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  /// La app con la sesión de [token] restaurada y el servidor de prueba detrás del cliente HTTP de producción.
  Future<ProviderContainer> signedInAs(String token, {Set<String>? revoked}) async {
    store['api_token'] = token;
    final c = ProviderContainer(overrides: [
      deviceNameProvider.overrideWith((ref) async => 'Motorola moto g32 · Android 14'),
    ]);
    addTearDown(c.dispose);
    c.read(apiClientProvider).dio.httpClientAdapter = _FakeAdapter((o) => _server(o, revoked ?? {}));

    c.read(authControllerProvider);
    await _until(c, AuthStatus.authenticated);
    return c;
  }

  Future<void> loginAsBeto(ProviderContainer c) =>
      c.read(authControllerProvider.notifier).login(email: 'beto@fonda.mx', password: 'secreta');

  test('al salir se descartan los permisos, el resumen, el rol y la sucursal de Ana; Beto ve sólo lo suyo', () async {
    final c = await signedInAs('tok-ana');

    var screens = _screens(c, [permissionsProvider, supervisionControllerProvider]);
    expect(await c.read(permissionsProvider.future), contains('pos.accounts.charge'));
    expect((await c.read(supervisionControllerProvider.future)).context.membershipName, 'Ana Gómez');
    expect(store['role_ulid'], 'ROLE-Gerente');

    // «Salir»: las pestañas se desmontan (v. HomeShell) y la sesión se cierra.
    for (final s in screens) {
      s.close();
    }
    await c.read(authControllerProvider.notifier).logout();
    await pumpEventQueue();

    // De Ana no queda nada: ni en memoria ni en el almacenamiento.
    expect(c.exists(permissionsProvider), isFalse);
    expect(c.exists(supervisionControllerProvider), isFalse);
    expect(store.containsKey('role_ulid'), isFalse);
    expect(store.containsKey('branch_ulid'), isFalse);

    // Entra Beto en el mismo aparato.
    await loginAsBeto(c);
    screens = _screens(c, [permissionsProvider, supervisionControllerProvider]);

    expect(await c.read(permissionsProvider.future), {'pos.accounts.view'});
    final beto = await c.read(supervisionControllerProvider.future);
    expect(beto.context.membershipName, 'Beto Ruiz');
    expect(beto.context.roleName, 'Mesero');
    expect(beto.context.branchName, 'Roma');
    expect(store['role_ulid'], 'ROLE-Mesero');
  });

  test('aunque una pantalla siguiera abierta durante el cambio, lo de Ana no se queda: se vuelve a pedir', () async {
    final c = await signedInAs('tok-ana');
    // Suscripciones que NO se cierran: el descarte no depende de que las pantallas se desmonten.
    _screens(c, [permissionsProvider, supervisionControllerProvider]);
    expect(await c.read(permissionsProvider.future), contains('pos.accounts.charge'));
    expect((await c.read(supervisionControllerProvider.future)).context.membershipName, 'Ana Gómez');

    await c.read(authControllerProvider.notifier).logout();
    for (var i = 0;
        i < 20 && (c.read(permissionsProvider).isLoading || c.read(supervisionControllerProvider).isLoading);
        i++) {
      await pumpEventQueue();
    }

    // Sin sesión, el servidor ya no reconoce a nadie: los permisos de Ana se fueron y el resumen no se muestra.
    expect(c.read(permissionsProvider).valueOrNull, isNot(contains('pos.accounts.charge')));
    expect(c.read(supervisionControllerProvider).hasError, isTrue);

    await loginAsBeto(c);

    expect(await c.read(permissionsProvider.future), {'pos.accounts.view'});
    expect((await c.read(supervisionControllerProvider.future)).context.membershipName, 'Beto Ruiz');
  });

  test('la época cambia al salir y al entrar, no al repetir el mismo estado', () async {
    final c = await signedInAs('tok-ana');
    final start = c.read(sessionEpochProvider);

    await c.read(authControllerProvider.notifier).logout();
    expect(c.read(sessionEpochProvider), start + 1);

    // Salir otra vez, ya sin sesión, no es un cambio: no hay nada más que descartar.
    await c.read(authControllerProvider.notifier).logout();
    expect(c.read(sessionEpochProvider), start + 1);

    await loginAsBeto(c);
    expect(c.read(sessionEpochProvider), start + 2);
  });

  test('los carritos sin mandar y el filtro de turnos no pasan a la siguiente sesión', () async {
    final c = await signedInAs('tok-ana');
    c.read(captureCartProvider('ACC-1').notifier).add(_taco);
    c.read(sessionsFilterProvider.notifier).state = 'closed';
    expect(c.read(captureCartProvider('ACC-1')), hasLength(1));

    await c.read(authControllerProvider.notifier).logout();

    expect(c.read(captureCartProvider('ACC-1')), isEmpty);
    expect(c.read(sessionsFilterProvider), 'open');
  });

  test('lo cargado con los repositorios (cuentas, turnos, reportes) se vuelve a pedir con la sesión nueva', () async {
    final c = await signedInAs('tok-ana');
    _screens(c, [openAccountsProvider, sessionsListProvider('open'), reportsListProvider]);
    expect((await c.read(openAccountsProvider.future)).single.displayName, 'Mesa de Ana Gómez');
    expect((await c.read(sessionsListProvider('open').future)).single.folio, 'Turno de Ana Gómez');
    expect((await c.read(reportsListProvider.future)).single.label, 'Ventas para Gerente');

    await c.read(authControllerProvider.notifier).logout();
    await loginAsBeto(c);

    expect((await c.read(openAccountsProvider.future)).single.displayName, 'Mesa de Beto Ruiz');
    expect((await c.read(sessionsListProvider('open').future)).single.folio, 'Turno de Beto Ruiz');
    expect((await c.read(reportsListProvider.future)).single.label, 'Ventas para Mesero');
  });

  test('la sesión revocada en el servidor (401) descarta lo mismo que «Salir»', () async {
    final revoked = <String>{};
    final c = await signedInAs('tok-ana', revoked: revoked);
    c.read(captureCartProvider('ACC-1').notifier).add(_taco);
    _screens(c, [permissionsProvider]);
    expect(await c.read(permissionsProvider.future), contains('pos.accounts.charge'));

    // Ana cambió su contraseña desde la web: su token dejó de valer y la siguiente petición vuelve 401.
    revoked.add('tok-ana');
    await c.read(apiClientProvider).dio.get<dynamic>('/pos-accounts');
    await _until(c, AuthStatus.unauthenticated);

    expect(c.read(captureCartProvider('ACC-1')), isEmpty);

    await loginAsBeto(c);
    expect(await c.read(permissionsProvider.future), {'pos.accounts.view'});
  });

  test('en el kiosco, el siguiente operador no hereda los permisos ni el resumen del anterior', () async {
    // Aparato emparejado: la API viaja con el token del DISPOSITIVO y el servidor responde según el operador en turno.
    store['shared_terminal_token'] = 'dev-1';
    var operator = _ana;
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(apiClientProvider).dio.httpClientAdapter = _FakeAdapter((o) {
      if (o.headers['X-Terminal-Token'] != 'dev-1') return _unauthenticated();
      return switch (o.path) {
        '/context' => _json({'data': operator.context}, 200),
        _ => _json({'data': <Object>[]}, 200),
      };
    });

    // Opera Ana: sus pantallas muestran lo suyo.
    var screens = _screens(c, [permissionsProvider, supervisionControllerProvider]);
    expect(await c.read(permissionsProvider.future), contains('pos.accounts.charge'));
    expect((await c.read(supervisionControllerProvider.future)).context.membershipName, 'Ana Gómez');

    // Ana bloquea (las pantallas se van) y se identifica Beto.
    for (final s in screens) {
      s.close();
    }
    await pumpEventQueue();
    operator = _beto;
    screens = _screens(c, [permissionsProvider, supervisionControllerProvider]);

    expect(await c.read(permissionsProvider.future), {'pos.accounts.view'});
    expect((await c.read(supervisionControllerProvider.future)).context.membershipName, 'Beto Ruiz');
  });
}
