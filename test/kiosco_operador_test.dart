import 'dart:async';
import 'dart:convert';

import 'package:comandia_app/core/providers.dart';
import 'package:comandia_app/features/pos/pos.dart';
import 'package:comandia_app/features/sessions/sessions.dart';
import 'package:comandia_app/features/shared_terminal/shared_terminal.dart';
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

/// El servidor del kiosco: valida código + PIN sobre el token del dispositivo y recuerda quién opera; `/context`
/// responde por ese operador. Si el operador caduca (inactividad), el POS responde 401.
class _KioskServer {
  static const _membershipByCode = {'ANA1': 'MEM-ANA', 'BETO2': 'MEM-BETO'};

  /// La membresía en turno, o `null` si no hay operador (bloqueo o caducado).
  String? operator;

  /// Para simular que el servidor no logra decir quién se identificó.
  bool contextFails = false;

  ResponseBody handle(RequestOptions o) {
    if (o.headers['X-Terminal-Token'] != 'dev-1') return _unauthenticated();

    if (o.path == '/shared-terminal/token/operator') {
      if (o.method == 'DELETE') {
        operator = null;
        return _empty(204);
      }
      final membership = _membershipByCode[(o.data as Map)['employee_code']];
      if (membership == null) return _json({'title': 'Código de empleado o PIN incorrectos.'}, 422);
      operator = membership;
      return _empty(204);
    }

    if (operator == null) return _unauthenticated();
    if (o.path == '/context') {
      if (contextFails) return _json({'message': 'Server Error'}, 503);
      return _json({
        'data': {
          'membership': {'ulid': operator, 'display_name': operator},
          'permissions': <String>[],
        },
      }, 200);
    }
    return _json({'data': <Object>[]}, 200);
  }
}

/// Deja correr la cola hasta que el kiosco llegue a [status]; si no llega, el expect lo dice.
Future<void> _until(ProviderContainer c, KioskStatus status) async {
  for (var i = 0; i < 20 && c.read(kioskControllerProvider) != status; i++) {
    await pumpEventQueue();
  }
  expect(c.read(kioskControllerProvider), status);
}

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

  /// Un aparato emparejado como kiosco, en el bloqueo, con [server] detrás del cliente HTTP de producción.
  Future<ProviderContainer> pairedKiosk(_KioskServer server) async {
    store['shared_terminal_token'] = 'dev-1';
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(apiClientProvider).dio.httpClientAdapter = _FakeAdapter(server.handle);

    c.read(kioskControllerProvider);
    await _until(c, KioskStatus.locked);
    return c;
  }

  Future<void> identify(ProviderContainer c, String employeeCode) =>
      c.read(kioskControllerProvider.notifier).identify(employeeCode: employeeCode, pin: '1234');

  /// Ana deja trabajo sin mandar: una línea en el carrito de la mesa y el filtro de turnos en «cerrados».
  void leaveUnsentWork(ProviderContainer c) {
    c.read(captureCartProvider('ACC-1').notifier).add(_taco);
    c.read(sessionsFilterProvider.notifier).state = 'closed';
  }

  /// El operador caduca en el servidor por inactividad: la siguiente petición del POS vuelve 401 y el kiosco se bloquea.
  Future<void> expireByInactivity(ProviderContainer c, _KioskServer server) async {
    server.operator = null;
    await c.read(apiClientProvider).dio.get<dynamic>('/pos-accounts');
    await _until(c, KioskStatus.locked);
  }

  test('si vuelve el MISMO operador tras bloquear, su carrito y su filtro siguen como los dejó', () async {
    final c = await pairedKiosk(_KioskServer());
    await identify(c, 'ANA1');
    leaveUnsentWork(c);

    await c.read(kioskControllerProvider.notifier).lock();
    await identify(c, 'ANA1');

    expect(c.read(kioskControllerProvider), KioskStatus.operating);
    expect(c.read(captureCartProvider('ACC-1')).single.name, 'Taco');
    expect(c.read(sessionsFilterProvider), 'closed');
  });

  test('si se identifica OTRO operador, lo que el anterior dejó sin mandar se descarta antes de que lo vea', () async {
    final c = await pairedKiosk(_KioskServer());
    await identify(c, 'ANA1');
    leaveUnsentWork(c);
    await c.read(kioskControllerProvider.notifier).lock();

    // Lo que hay en el carrito justo cuando Beto empieza a operar (lo primero que podría ver).
    List<CaptureLine>? cartWhenBetoStarts;
    c.listen(kioskControllerProvider, (_, next) {
      if (next == KioskStatus.operating) cartWhenBetoStarts = c.read(captureCartProvider('ACC-1'));
    });
    await identify(c, 'BETO2');

    expect(cartWhenBetoStarts, isEmpty);
    expect(c.read(captureCartProvider('ACC-1')), isEmpty);
    expect(c.read(sessionsFilterProvider), 'open');
    // Lo del aparato no se toca: sigue emparejado.
    expect(store['shared_terminal_token'], 'dev-1');
  });

  test('tras caducar por inactividad (401), el mismo operador recupera lo que dejó sin mandar', () async {
    final server = _KioskServer();
    final c = await pairedKiosk(server);
    await identify(c, 'ANA1');
    leaveUnsentWork(c);

    await expireByInactivity(c, server);
    await identify(c, 'ANA1');

    expect(c.read(captureCartProvider('ACC-1')).single.name, 'Taco');
    expect(c.read(sessionsFilterProvider), 'closed');
  });

  test('tras caducar por inactividad (401), otro operador no hereda lo que quedó sin mandar', () async {
    final server = _KioskServer();
    final c = await pairedKiosk(server);
    await identify(c, 'ANA1');
    leaveUnsentWork(c);

    await expireByInactivity(c, server);
    await identify(c, 'BETO2');

    expect(c.read(captureCartProvider('ACC-1')), isEmpty);
    expect(c.read(sessionsFilterProvider), 'open');
  });

  test('si el servidor no confirma quién se identificó, se trata como otra persona y se descarta', () async {
    final server = _KioskServer();
    final c = await pairedKiosk(server);
    await identify(c, 'ANA1');
    leaveUnsentWork(c);
    await c.read(kioskControllerProvider.notifier).lock();

    server.contextFails = true;
    await identify(c, 'ANA1');

    // Se opera igual (el PIN fue válido), pero sin heredar nada.
    expect(c.read(kioskControllerProvider), KioskStatus.operating);
    expect(c.read(captureCartProvider('ACC-1')), isEmpty);
    expect(c.read(sessionsFilterProvider), 'open');
  });
}
