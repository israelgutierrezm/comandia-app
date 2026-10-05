import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:comandia_app/core/api_client.dart';
import 'package:comandia_app/core/providers.dart';
import 'package:comandia_app/core/token_storage.dart';
import 'package:comandia_app/features/auth/auth.dart';
import 'package:comandia_app/features/shared_terminal/shared_terminal.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Adaptador HTTP simulado. `handler` puede devolver un Future: así se simula un servidor que nunca contesta.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);
  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

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

/// Lo que responde el servidor a un token revocado o caducado.
ResponseBody _unauthenticated() =>
    _json({'type': 'unauthenticated', 'title': 'No has iniciado sesión.', 'status': 401}, 401);

/// Un repositorio cuyo cierre en el servidor revienta: la salida local no debe depender de él.
class _ThrowingAuthRepository extends AuthRepository {
  _ThrowingAuthRepository(super.api);

  @override
  Future<void> logout() async => throw Exception('falla inesperada');
}

/// Deja correr la cola hasta que la sesión llegue a [status]; si no llega, el expect lo dice.
Future<void> _until(ProviderContainer c, AuthStatus status) async {
  for (var i = 0; i < 20 && c.read(authControllerProvider) != status; i++) {
    await pumpEventQueue();
  }
  expect(c.read(authControllerProvider), status);
}

void main() {
  // Almacenamiento seguro en memoria (write/read/delete) y bitácora de las llaves borradas.
  final store = <String, String>{};
  final deleted = <String>[];
  // Simula un almacén dañado (p. ej. el Keystore de Android): borrar falla.
  var failDeletes = false;

  setUp(() {
    store.clear();
    deleted.clear();
    failDeletes = false;
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        // Como en un aparato real, la respuesta de la plataforma llega en otro turno del ciclo de eventos (no en una
        // microtarea): así las respuestas simultáneas del cliente HTTP se entrelazan de verdad.
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
            if (failDeletes) throw PlatformException(code: 'storage', message: 'Almacén dañado');
            if (key != null) {
              store.remove(key);
              deleted.add(key);
            }
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

  /// La app con una sesión de usuario restaurada (token, rol y sucursal) y el cliente HTTP de producción —con su
  /// cableado de 401— respondiendo con [handler].
  Future<ProviderContainer> signedIn(
    FutureOr<ResponseBody> Function(RequestOptions options) handler, {
    List<Override> overrides = const [],
  }) async {
    store
      ..['api_token'] = 'tok-1'
      ..['role_ulid'] = 'ROLE1'
      ..['branch_ulid'] = 'BR1';

    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    container.read(apiClientProvider).dio.httpClientAdapter = _FakeAdapter(handler);

    // Al arrancar, la sesión se restaura del token guardado.
    container.read(authControllerProvider);
    await _until(container, AuthStatus.authenticated);
    return container;
  }

  test('el login da de alta el aparato con su nombre legible (device_name)', () async {
    RequestOptions? got;
    final c = ProviderContainer(overrides: [
      deviceNameProvider.overrideWith((ref) async => 'Motorola moto g32 · Android 14'),
    ]);
    addTearDown(c.dispose);
    c.read(apiClientProvider).dio.httpClientAdapter = _FakeAdapter((o) {
      got = o;
      return _json({'token': 'tok-1', 'context': <String, dynamic>{}}, 201);
    });

    await c.read(authControllerProvider.notifier).login(email: 'ana@fonda.mx', password: 'secreta');

    expect(got!.path, '/auth/token');
    expect(got!.data['device_name'], 'Motorola moto g32 · Android 14');
    expect(store['api_token'], 'tok-1');
    expect(c.read(authControllerProvider), AuthStatus.authenticated);
  });

  test('AuthRepository.logout nunca lanza: sin red, servidor caído, ya revocado (401) o sin respuesta', () async {
    store['api_token'] = 'tok-1';
    final servers = <FutureOr<ResponseBody> Function(RequestOptions)>[
      (o) => throw const SocketException('Sin conexión'),
      (o) => _json({'message': 'Server Error'}, 503),
      (o) => _unauthenticated(),
      (o) => Completer<ResponseBody>().future,
    ];

    for (final server in servers) {
      final api = ApiClient(const TokenStorage(FlutterSecureStorage()))..dio.httpClientAdapter = _FakeAdapter(server);
      await AuthRepository(api, logoutTimeout: const Duration(milliseconds: 50)).logout();
    }
  });

  group('AuthController.logout', () {
    test('revoca el token en el servidor (DELETE auth/token con ese token) y cierra la sesión local', () async {
      RequestOptions? got;
      final c = await signedIn((o) {
        got = o;
        return _empty(204);
      });

      await c.read(authControllerProvider.notifier).logout();

      expect(got!.method, 'DELETE');
      expect(got!.path, '/auth/token');
      expect(got!.headers['Authorization'], 'Bearer tok-1');
      expect(c.read(authControllerProvider), AuthStatus.unauthenticated);
      // Ni token, ni rol, ni sucursal.
      expect(store, isEmpty);
    });

    test('sin red, la sesión local se cierra igual', () async {
      final c = await signedIn((o) => throw const SocketException('Sin conexión'));

      await c.read(authControllerProvider.notifier).logout();

      expect(c.read(authControllerProvider), AuthStatus.unauthenticated);
      expect(store, isEmpty);
    });

    test('si el cierre en el servidor lanza, la sesión local se cierra igual', () async {
      final c = await signedIn(
        (o) => _empty(204),
        overrides: [
          authRepositoryProvider.overrideWith((ref) => _ThrowingAuthRepository(ref.watch(apiClientProvider))),
        ],
      );

      await c.read(authControllerProvider.notifier).logout();

      expect(c.read(authControllerProvider), AuthStatus.unauthenticated);
      expect(store, isEmpty);
    });

    test('un servidor que no contesta no atora la salida', () async {
      final c = await signedIn(
        // Nunca responde.
        (o) => Completer<ResponseBody>().future,
        overrides: [
          authRepositoryProvider.overrideWith(
            (ref) => AuthRepository(ref.watch(apiClientProvider), logoutTimeout: const Duration(milliseconds: 50)),
          ),
        ],
      );

      // Si la salida esperara al servidor (que nunca contesta), este límite reventaría la prueba. Es holgado a propósito
      // frente a los 50 ms: sólo debe romperse si la espera no tiene fin, no porque la máquina vaya lenta.
      await c.read(authControllerProvider.notifier).logout().timeout(const Duration(seconds: 10));

      expect(c.read(authControllerProvider), AuthStatus.unauthenticated);
      expect(store, isEmpty);
    });

    test('si el almacenamiento falla al borrar, el error se reporta pero la app igual sale al acceso', () async {
      final c = await signedIn((o) => _empty(204));
      failDeletes = true;

      await expectLater(c.read(authControllerProvider.notifier).logout(), throwsA(isA<PlatformException>()));

      expect(c.read(authControllerProvider), AuthStatus.unauthenticated);
    });

    test('un 401 (el token ya estaba revocado) cuenta como éxito y no dispara además el aviso de sesión revocada',
        () async {
      final c = await signedIn((o) => _unauthenticated());

      await c.read(authControllerProvider.notifier).logout();
      await pumpEventQueue();

      expect(c.read(authControllerProvider), AuthStatus.unauthenticated);
      expect(store, isEmpty);
      expect(c.read(userUnauthorizedTickProvider), 0);
      // La sesión local se limpió una sola vez.
      expect(deleted.where((k) => k == 'api_token'), hasLength(1));
    });
  });

  group('401 con el token del usuario (sesión revocada en el servidor)', () {
    test('cierra la sesión local y manda al acceso, UNA sola vez aunque fallen varias peticiones a la vez', () async {
      // Las tres respuestas se sueltan juntas, cuando ya llegaron las tres peticiones: así compiten de verdad (todas
      // leen el token guardado antes de que la primera alcance a borrarlo).
      final pending = <Completer<ResponseBody>>[];
      final c = await signedIn((o) {
        final response = Completer<ResponseBody>();
        pending.add(response);
        if (pending.length == 3) {
          for (final p in pending) {
            p.complete(_unauthenticated());
          }
        }
        return response.future;
      });
      final api = c.read(apiClientProvider);

      await Future.wait([
        api.dio.get<dynamic>('/context'),
        api.dio.get<dynamic>('/pos-accounts'),
        api.dio.get<dynamic>('/pos-sessions'),
      ]);
      await _until(c, AuthStatus.unauthenticated);

      expect(store, isEmpty);
      expect(c.read(userUnauthorizedTickProvider), 1);
      expect(deleted.where((k) => k == 'api_token'), hasLength(1));
    });

    test('el login con contraseña equivocada (401 o 422 en POST auth/token) no cierra ninguna sesión', () async {
      var loginStatus = 401;
      final c = await signedIn((o) {
        if (o.path == '/auth/token') {
          return _json({'message': 'Estas credenciales no coinciden con nuestros registros.'}, loginStatus);
        }
        return _unauthenticated();
      });

      // Aun si viajara un token guardado, un login fallido habla de la contraseña, no de la sesión.
      for (final status in [401, 422]) {
        loginStatus = status;
        await expectLater(
          c.read(authRepositoryProvider).login(email: 'ana@fonda.mx', password: 'mala', deviceName: 'Prueba'),
          throwsA(isA<AuthException>()),
        );
      }
      await pumpEventQueue();

      expect(c.read(userUnauthorizedTickProvider), 0);
      expect(store['api_token'], 'tok-1');
      expect(c.read(authControllerProvider), AuthStatus.authenticated);

      // Control: el mismo 401 fuera del login sí cierra la sesión (el manejador estaba vivo).
      await c.read(apiClientProvider).dio.get<dynamic>('/context');
      await _until(c, AuthStatus.unauthenticated);
    });

    test('emparejar el kiosco con un secreto inválido (401) no toca la sesión del usuario', () async {
      final c = await signedIn((o) {
        if (o.path == '/shared-terminal/token') {
          return _json({
            'type': 'invalid_device_secret',
            'title': 'El secreto del dispositivo no es válido o fue revocado.',
          }, 401);
        }
        return _unauthenticated();
      });

      await expectLater(c.read(sharedTerminalRepositoryProvider).pair('D1|malo'), throwsA(isA<PairError>()));
      await pumpEventQueue();

      expect(c.read(userUnauthorizedTickProvider), 0);
      expect(store['api_token'], 'tok-1');
      expect(c.read(authControllerProvider), AuthStatus.authenticated);
    });

    test('en modo kiosco no toca la sesión del usuario: el 401 sigue mandando al bloqueo', () async {
      RequestOptions? got;
      final c = await signedIn((o) {
        got = o;
        return _unauthenticated();
      });
      // El aparato quedó emparejado como terminal compartida: la API viaja con el token del DISPOSITIVO.
      store['shared_terminal_token'] = 'dev-1';

      await c.read(apiClientProvider).dio.get<dynamic>('/pos-accounts');
      await pumpEventQueue();

      expect(got!.headers['X-Terminal-Token'], 'dev-1');
      expect(got!.headers.containsKey('Authorization'), isFalse);
      expect(c.read(kioskUnauthorizedTickProvider), 1);
      expect(c.read(userUnauthorizedTickProvider), 0);
      expect(store['api_token'], 'tok-1');
      expect(c.read(authControllerProvider), AuthStatus.authenticated);
    });

    test('un 401 tardío de una sesión anterior no tumba la sesión nueva', () async {
      final c = await signedIn((o) {
        // Mientras esta petición viajaba con 'tok-1', la persona salió y volvió a entrar: ya hay otro token guardado.
        store['api_token'] = 'tok-2';
        return _unauthenticated();
      });

      await c.read(apiClientProvider).dio.get<dynamic>('/context');
      await pumpEventQueue();

      expect(c.read(userUnauthorizedTickProvider), 0);
      expect(store['api_token'], 'tok-2');
      expect(c.read(authControllerProvider), AuthStatus.authenticated);
    });

    test('tras volver a entrar, un 401 del token nuevo vuelve a cerrar la sesión (una vez por token)', () async {
      final c = await signedIn(
        (o) {
          if (o.path == '/auth/token') return _json({'token': 'tok-2', 'context': <String, dynamic>{}}, 201);
          return _unauthenticated();
        },
        overrides: [deviceNameProvider.overrideWith((ref) async => 'Apple iPhone 13 · iOS 17.5')],
      );
      final api = c.read(apiClientProvider);

      await api.dio.get<dynamic>('/context');
      await _until(c, AuthStatus.unauthenticated);

      await c.read(authControllerProvider.notifier).login(email: 'ana@fonda.mx', password: 'secreta');
      expect(store['api_token'], 'tok-2');
      expect(c.read(authControllerProvider), AuthStatus.authenticated);

      await api.dio.get<dynamic>('/context');
      await _until(c, AuthStatus.unauthenticated);
      expect(c.read(userUnauthorizedTickProvider), 2);
    });
  });
}
