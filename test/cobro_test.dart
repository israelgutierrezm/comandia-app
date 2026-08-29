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
  test('PaymentMethod.fromJson lee las banderas de comportamiento', () {
    final m = PaymentMethod.fromJson({
      'ulid': 'M1',
      'name': 'Tarjeta',
      'allows_change': false,
      'requires_reference': true,
      'affects_cash_drawer': false,
    });
    expect(m.name, 'Tarjeta');
    expect(m.requiresReference, isTrue);
    expect(m.allowsChange, isFalse);
  });

  test('PaymentLine.toJson arma el pago y omite lo vacío', () {
    final efectivo = PaymentMethod(
      ulid: 'M1',
      name: 'Efectivo',
      allowsChange: true,
      requiresReference: false,
      affectsCashDrawer: true,
    );
    final j = PaymentLine(method: efectivo, amount: '90.00', tendered: '100.00', tip: '10.00').toJson();

    expect(j['payment_method_ulid'], 'M1');
    expect(j['amount'], '90.00');
    expect(j['tendered_amount'], '100.00');
    expect(j['tip_amount'], '10.00');
    // Sin referencia: la llave ni siquiera va.
    expect(j.containsKey('reference'), isFalse);
  });

  group('PosRepository.charge', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      // El interceptor del cliente lee el token del almacenamiento seguro; sin plataforma, devolvemos nulo.
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

    final efectivo = PaymentMethod(
      ulid: 'M1',
      name: 'Efectivo',
      allowsChange: true,
      requiresReference: false,
      affectsCashDrawer: true,
    );

    test('postea los pagos con la versión y devuelve la cuenta pagada', () async {
      RequestOptions? posted;
      final adapter = _FakeAdapter((o) {
        posted = o;
        return _json({
          'data': {
            'ulid': 'A1',
            'display_name': 'Mesa 1',
            'folio': 'A-1',
            'status_label': 'Pagada',
            'version': 4,
            'accepts_items': false,
            'totals': {'total': '90.00', 'due': '0.00', 'change_total': '10.00'},
            'items': [],
            'orders': [],
          },
        }, 200);
      });

      final account = await buildRepo(adapter).charge('A1', 3, [PaymentLine(method: efectivo, amount: '90.00', tendered: '100.00')]);

      expect(account.totals['due'], '0.00');
      expect(account.totals['change_total'], '10.00');
      expect(posted!.data['version'], 3);
      expect((posted!.data['payments'] as List).single['amount'], '90.00');
      expect((posted!.data['payments'] as List).single['tendered_amount'], '100.00');
    });

    test('409 se traduce a StaleAccount', () async {
      final adapter = _FakeAdapter((o) => _json({'message': 'stale'}, 409));
      await expectLater(
        buildRepo(adapter).charge('A1', 3, [PaymentLine(method: efectivo, amount: '10.00')]),
        throwsA(isA<StaleAccount>()),
      );
    });

    test('422 se traduce a ChargeError con el mensaje del servidor', () async {
      final adapter = _FakeAdapter((o) => _json({'message': 'El monto excede lo que falta.'}, 422));
      await expectLater(
        buildRepo(adapter).charge('A1', 3, [PaymentLine(method: efectivo, amount: '999.00')]),
        throwsA(isA<ChargeError>().having((e) => e.message, 'mensaje', contains('excede'))),
      );
    });

    test('discount lanza NeedsAuthorization en 409 authorization_required', () async {
      final adapter = _FakeAdapter(
        (o) => _json({'type': 'authorization_required', 'required_permission': 'pos.discounts.apply'}, 409),
      );
      await expectLater(
        buildRepo(adapter).discount('A1', 3, kind: 'percentage', value: '10', reason: 'Cliente frecuente'),
        throwsA(isA<NeedsAuthorization>().having((e) => e.permission, 'permiso', 'pos.discounts.apply')),
      );
    });

    test('discount postea el descuento (con token) y devuelve la cuenta', () async {
      RequestOptions? got;
      final adapter = _FakeAdapter((o) {
        got = o;
        return _json({
          'data': {
            'ulid': 'A1',
            'display_name': 'Mesa 1',
            'folio': 'A-1',
            'status': 'open',
            'status_label': 'Abierta',
            'version': 4,
            'accepts_items': true,
            'totals': {'discount_total': '20.00', 'due': '80.00'},
            'items': [],
            'orders': [],
          },
        }, 200);
      });

      final acc = await buildRepo(adapter)
          .discount('A1', 3, kind: 'amount', value: '20.00', reason: 'Cortesía del gerente', authorizationToken: 'TKN-1');

      expect(acc.totals['discount_total'], '20.00');
      expect(got!.data['kind'], 'amount');
      expect(got!.data['reason'], 'Cortesía del gerente');
      expect(got!.data['authorization_token'], 'TKN-1');
    });

    test('authorize canjea el PIN por un token', () async {
      RequestOptions? got;
      final adapter = _FakeAdapter((o) {
        got = o;
        return _json({
          'data': {'token': 'TKN-1', 'authorized_by': {'name': 'Gerente'}},
        }, 200);
      });

      final token = await buildRepo(adapter).authorize('1234', 'pos.discounts.apply');

      expect(token, 'TKN-1');
      expect(got!.path, '/authorizations');
      expect(got!.data['pin'], '1234');
      expect(got!.data['permission'], 'pos.discounts.apply');
    });
  });
}
