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
  test('RestaurantTable.fromJson usa name, o code si falta, y la zona', () {
    final t = RestaurantTable.fromJson({
      'ulid': 'T1',
      'code': 'M4',
      'name': 'Mesa 4',
      'seats': 4,
      'zone': {'name': 'Terraza'},
    });
    expect(t.label, 'Mesa 4');
    expect(t.seats, 4);
    expect(t.zoneName, 'Terraza');

    final noName = RestaurantTable.fromJson({'ulid': 'T2', 'code': 'B1'});
    expect(noName.label, 'B1'); // cae al código
    expect(noName.zoneName, isNull);
  });

  group('PosRepository mesas', () {
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

    PosRepository buildRepo(_FakeAdapter adapter) {
      final storage = TokenStorage(const FlutterSecureStorage());
      final api = ApiClient(storage);
      api.dio.httpClientAdapter = adapter;
      return PosRepository(api, storage);
    }

    test('availableTables pide available_only y la sucursal activa', () async {
      RequestOptions? got;
      final adapter = _FakeAdapter((o) {
        got = o;
        return _json({
          'data': [
            {'ulid': 'T1', 'name': 'Mesa 1', 'seats': 2},
          ],
        }, 200);
      });

      final tables = await buildRepo(adapter).availableTables();

      expect(tables.single.label, 'Mesa 1');
      expect(got!.queryParameters['available_only'], 1);
      expect(got!.queryParameters['branch'], 'BR1');
    });

    test('openTable postea table_ulid y devuelve la cuenta', () async {
      RequestOptions? got;
      final adapter = _FakeAdapter((o) {
        got = o;
        return _json({
          'data': {'ulid': 'A9', 'display_name': 'Mesa 4', 'folio': 'A-9', 'status_label': 'Abierta'},
        }, 201);
      });

      final account = await buildRepo(adapter).openTable('T4');

      expect(account.ulid, 'A9');
      expect(account.displayName, 'Mesa 4');
      expect(got!.data['table_ulid'], 'T4');
    });
  });
}
