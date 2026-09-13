import 'dart:convert';

import 'package:comandia_app/core/api_client.dart';
import 'package:comandia_app/core/shared_terminal_storage.dart';
import 'package:comandia_app/core/token_storage.dart';
import 'package:comandia_app/features/shared_terminal/shared_terminal.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

void main() {
  // Almacenamiento seguro en memoria para el grupo (write/read/delete).
  final store = <String, String>{};

  setUp(() {
    store.clear();
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
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
          case 'readAll':
            return Map<String, String>.from(store);
          case 'deleteAll':
            store.clear();
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

  SharedTerminalRepository buildRepo(_FakeAdapter adapter) {
    final shared = const SharedTerminalStorage(FlutterSecureStorage());
    final api = ApiClient(const TokenStorage(FlutterSecureStorage()), shared);
    api.dio.httpClientAdapter = adapter;
    return SharedTerminalRepository(api, shared);
  }

  test('pair canjea el secreto, guarda el token y devuelve la terminal y sucursal', () async {
    RequestOptions? got;
    final adapter = _FakeAdapter((o) {
      got = o;
      return _json({
        'data': {'ulid': 'D1', 'label': 'Tablet caja', 'terminal': {'name': 'Caja 1'}},
        'token': 'tok-secreto-123',
        'branch': {'ulid': 'BR1', 'name': 'Centro'},
      }, 200);
    });

    final paired = await buildRepo(adapter).pair('D1|elsecreto');

    expect(got!.path, '/shared-terminal/token');
    expect(got!.data['secret'], 'D1|elsecreto');
    expect(paired.terminalName, 'Caja 1');
    expect(paired.branchName, 'Centro');
    // El token quedó guardado para que ApiClient lo reenvíe como X-Terminal-Token.
    expect(store['shared_terminal_token'], 'tok-secreto-123');
    expect(store['shared_terminal_name'], 'Caja 1');
  });

  test('pair lanza PairError con 401', () async {
    final adapter = _FakeAdapter((_) => _json({
          'type': 'invalid_device_secret',
          'title': 'El secreto del dispositivo no es válido o fue revocado.',
        }, 401));

    await expectLater(buildRepo(adapter).pair('D1|malo'), throwsA(isA<PairError>()));
    expect(store.containsKey('shared_terminal_token'), isFalse);
  });

  test('identify postea código y PIN y acepta 204', () async {
    RequestOptions? got;
    final adapter = _FakeAdapter((o) {
      got = o;
      return _empty(204);
    });

    await buildRepo(adapter).identify(employeeCode: 'MESERO1', pin: '1234');

    expect(got!.path, '/shared-terminal/token/operator');
    expect(got!.data['employee_code'], 'MESERO1');
    expect(got!.data['pin'], '1234');
  });

  test('identify lanza IdentifyError (no bloqueado) con 422', () async {
    final adapter = _FakeAdapter((_) => _json({'title': 'Código de empleado o PIN incorrectos.'}, 422));

    await expectLater(
      buildRepo(adapter).identify(employeeCode: 'X', pin: '9999'),
      throwsA(isA<IdentifyError>().having((e) => e.locked, 'locked', isFalse)),
    );
  });

  test('identify lanza IdentifyError bloqueado con 423', () async {
    final adapter = _FakeAdapter((_) => _json({'title': 'PIN bloqueado.'}, 423));

    await expectLater(
      buildRepo(adapter).identify(employeeCode: 'MESERO1', pin: '1234'),
      throwsA(isA<IdentifyError>().having((e) => e.locked, 'locked', isTrue)),
    );
  });

  test('release manda DELETE al endpoint de operador', () async {
    RequestOptions? got;
    final adapter = _FakeAdapter((o) {
      got = o;
      return _empty(204);
    });

    await buildRepo(adapter).release();

    expect(got!.method, 'DELETE');
    expect(got!.path, '/shared-terminal/token/operator');
  });
}
