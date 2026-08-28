import 'dart:convert';

import 'package:comandia_app/core/api_client.dart';
import 'package:comandia_app/core/token_storage.dart';
import 'package:comandia_app/features/sessions/sessions.dart';
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

void main() {
  test('Terminal.fromJson lee nombre y sucursal', () {
    final t = Terminal.fromJson({
      'ulid': 'TERM1',
      'name': 'Caja 1',
      'branch': {'name': 'Matriz'},
    });
    expect(t.name, 'Caja 1');
    expect(t.branchName, 'Matriz');
  });

  group('SessionsRepository caja', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async {
          if (call.method == 'read' && (call.arguments as Map)['key'] == 'branch_ulid') return 'BR1';
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        null,
      );
    });

    SessionsRepository buildRepo(_FakeAdapter adapter) {
      final storage = TokenStorage(const FlutterSecureStorage());
      final api = ApiClient(storage);
      api.dio.httpClientAdapter = adapter;
      return SessionsRepository(api, storage);
    }

    test('terminals pide activas y la sucursal activa', () async {
      RequestOptions? got;
      final adapter = _FakeAdapter((o) {
        got = o;
        return _json({
          'data': [
            {'ulid': 'T1', 'name': 'Caja 1'},
          ],
        }, 200);
      });

      final terminals = await buildRepo(adapter).terminals();

      expect(terminals.single.name, 'Caja 1');
      expect(got!.queryParameters['status'], 'active');
      expect(got!.queryParameters['branch'], 'BR1');
    });

    test('openSession postea terminal y fondo', () async {
      RequestOptions? got;
      final adapter = _FakeAdapter((o) {
        got = o;
        return _json({'data': {'ulid': 'S1'}}, 201);
      });

      await buildRepo(adapter).openSession('T1', '500.00');

      expect(got!.path, '/pos-sessions');
      expect(got!.data['terminal_ulid'], 'T1');
      expect(got!.data['opening_float'], '500.00');
    });

    test('declare postea moment y las declaraciones', () async {
      RequestOptions? got;
      final adapter = _FakeAdapter((o) {
        got = o;
        return _json({'data': {}}, 200);
      });

      await buildRepo(adapter).declare('S1', 'close', [
        {'payment_method_ulid': 'M1', 'declared_amount': '1200.00'},
      ]);

      expect(got!.path, '/pos-sessions/S1/declarations');
      expect(got!.data['moment'], 'close');
      expect((got!.data['declarations'] as List).single['declared_amount'], '1200.00');
    });

    test('closeSession sin notas no manda la llave', () async {
      RequestOptions? got;
      final adapter = _FakeAdapter((o) {
        got = o;
        return _json({'data': {}}, 200);
      });

      await buildRepo(adapter).closeSession('S1');

      expect(got!.path, '/pos-sessions/S1/close');
      expect((got!.data as Map).containsKey('notes'), isFalse);
    });

    test('un 422 se traduce a CajaError con el mensaje del servidor', () async {
      final adapter = _FakeAdapter((o) => _json({'message': 'El fondo no puede ser negativo.'}, 422));
      await expectLater(
        buildRepo(adapter).openSession('T1', '-1'),
        throwsA(isA<CajaError>().having((e) => e.message, 'mensaje', contains('negativo'))),
      );
    });
  });
}
