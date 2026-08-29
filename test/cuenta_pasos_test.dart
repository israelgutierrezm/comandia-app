import 'dart:convert';

import 'package:comandia_app/core/api_client.dart';
import 'package:comandia_app/core/token_storage.dart';
import 'package:comandia_app/features/pos/pos.dart';
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
  test('Account.fromJson lee el estado crudo del ciclo de vida', () {
    final a = Account.fromJson({
      'ulid': 'A1',
      'display_name': 'Mesa 1',
      'folio': 'A-1',
      'status': 'bill_requested',
      'status_label': 'Cuenta solicitada',
      'version': 2,
      'accepts_items': false,
      'totals': {},
      'items': [],
      'orders': [],
    });
    expect(a.status, 'bill_requested');
  });

  group('PosRepository pasos de la cuenta', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => null,
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        null,
      );
    });

    PosRepository buildRepo(_FakeAdapter adapter) {
      final storage = TokenStorage(const FlutterSecureStorage());
      final api = ApiClient(storage);
      api.dio.httpClientAdapter = adapter;
      return PosRepository(api, storage);
    }

    test('requestBill postea la versión a bill-request', () async {
      RequestOptions? got;
      final adapter = _FakeAdapter((o) {
        got = o;
        return _json({'data': {}}, 200);
      });

      await buildRepo(adapter).requestBill('A1', 3);

      expect(got!.path, '/pos-accounts/A1/bill-request');
      expect(got!.data['version'], 3);
    });

    test('reopen postea a reopen y traduce 409 a StaleAccount', () async {
      final adapter = _FakeAdapter((o) => _json({'message': 'stale'}, 409));

      await expectLater(buildRepo(adapter).reopen('A1', 3), throwsA(isA<StaleAccount>()));
    });
  });
}
