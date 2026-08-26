import 'dart:convert';

import 'package:comandia_app/features/printing/escpos.dart';
import 'package:comandia_app/features/printing/print_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// ¿Aparece la subsecuencia `needle` dentro de `hay`?
bool _containsSeq(List<int> hay, List<int> needle) {
  for (var i = 0; i + needle.length <= hay.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}

void main() {
  // El corte total: GS V 0.
  const cut = [0x1D, 0x56, 0x00];

  test('renderTicket arma una comanda (sin dinero) y corta al final', () {
    final bytes = renderTicket({
      'kind_label': 'Comanda',
      'business': {'name': 'Cocina'},
      'account': {'display_name': 'Mesa 4'},
      'area': 'Barra',
      'items': [
        {'quantity': 2, 'name': 'Taco', 'modifiers': [{'name': 'sin cebolla'}]},
        {'quantity': 1, 'name': 'Agua', 'modifiers': []},
      ],
    }, charset: Charset.ascii);

    final text = latin1.decode(bytes);
    expect(text, contains('Cocina'));
    expect(text, contains('Mesa 4'));
    expect(text, contains('2 x Taco'));
    expect(text, contains('+ sin cebolla'));
    // Una comanda no lleva totales.
    expect(text, isNot(contains('Total')));
    // Termina cortando el papel.
    expect(bytes.sublist(bytes.length - cut.length), cut);
  });

  test('renderTicket desglosa el ticket final con totales y pagos', () {
    final bytes = renderTicket({
      'kind_label': 'Cuenta',
      'business': {'name': 'La Fonda'},
      'account': {'display_name': 'Mesa 1'},
      'items': [
        {'quantity': 2, 'name': 'Enchiladas', 'line_total': '90.00', 'modifiers': []},
      ],
      'totals': {'subtotal': '77.59', 'vat_total': '12.41', 'total': '90.00', 'change_total': '10.00'},
      'payments': [
        {'method': 'Efectivo', 'amount': '100.00'},
      ],
    }, charset: Charset.ascii);

    final text = latin1.decode(bytes);
    expect(text, contains('Subtotal'));
    expect(text, contains('IVA incluido'));
    expect(text, contains('Total'));
    expect(text, contains('\$90.00'));
    expect(text, contains('Efectivo'));
    expect(text, contains('Cambio'));
  });

  group('páginas de códigos', () {
    // «Café» = C a f é
    const cafe = [0x43, 0x61, 0x66];

    test('ASCII pliega los acentos y no manda ESC t', () {
      final b = EscPos(charset: Charset.ascii)..text('Café Ñandú ¿órale?');
      final bytes = b.bytes();
      expect(latin1.decode(bytes), contains('Cafe Nandu ?orale?'));
      // Sin selector de página.
      expect(_containsSeq(bytes, [0x1B, 0x74]), isFalse);
      // Ningún byte alto: se plegó, no se codificó crudo.
      expect(bytes.where((x) => x > 126 && x < 160), isEmpty);
    });

    test('CP850 codifica é=0x82 y selecciona ESC t 2', () {
      final bytes = (EscPos(charset: Charset.cp850)..text('Café')).bytes();
      expect(_containsSeq(bytes, [0x1B, 0x74, 0x02]), isTrue);
      expect(_containsSeq(bytes, [...cafe, 0x82]), isTrue); // é en CP850
    });

    test('CP1252 codifica é=0xE9 y selecciona ESC t 16', () {
      final bytes = (EscPos(charset: Charset.cp1252)..text('Café')).bytes();
      expect(_containsSeq(bytes, [0x1B, 0x74, 0x10]), isTrue);
      expect(_containsSeq(bytes, [...cafe, 0xE9]), isTrue); // é en CP1252/Latin-1
    });

    test('Charset.fromName cae en CP850 ante lo desconocido', () {
      expect(Charset.fromName('cp1252'), Charset.cp1252);
      expect(Charset.fromName(null), Charset.cp850);
      expect(Charset.fromName('marciano'), Charset.cp850);
    });
  });

  test('PrintJob.fromJson lee la impresora y el payload', () {
    final job = PrintJob.fromJson({
      'ulid': 'JOB1',
      'kind': 'kitchen_command',
      'kind_label': 'Comanda',
      'printer': {
        'name': 'Cocina',
        'connection': 'network',
        'target': '192.168.1.50:9100',
        'paper_width': 80,
        'supports_cash_drawer': false,
      },
      'payload': {'business': {'name': 'Cocina'}},
    });

    expect(job.ulid, 'JOB1');
    expect(job.kindLabel, 'Comanda');
    expect(job.connection, 'network');
    expect(job.target, '192.168.1.50:9100');
    expect(job.paperWidth, 80);
    expect(job.supportsCashDrawer, isFalse);
    expect(job.payload['business']['name'], 'Cocina');
  });

  group('PrintAgentStorage', () {
    late Map<String, String?> mem;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      mem = {};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async {
          final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
          switch (call.method) {
            case 'write':
              mem[args['key'] as String] = args['value'] as String?;
              return null;
            case 'read':
              return mem[args['key'] as String];
            case 'delete':
              mem.remove(args['key'] as String);
              return null;
            case 'containsKey':
              return mem.containsKey(args['key'] as String);
            case 'readAll':
              return mem;
            case 'deleteAll':
              mem.clear();
              return null;
          }
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

    test('idempotencia: marca y reconoce trabajos ya impresos', () async {
      const store = PrintAgentStorage(FlutterSecureStorage());

      expect(await store.isPrinted('JOB1'), isFalse);
      await store.markPrinted('JOB1');
      expect(await store.isPrinted('JOB1'), isTrue);

      // Marcar dos veces no duplica ni rompe.
      await store.markPrinted('JOB1');
      expect(await store.isPrinted('JOB1'), isTrue);
      expect(await store.isPrinted('OTRO'), isFalse);
    });

    test('guarda y lee la página de códigos', () async {
      const store = PrintAgentStorage(FlutterSecureStorage());

      expect(await store.readCharset(), isNull);
      await store.saveCharset(Charset.cp1252.name);
      expect(Charset.fromName(await store.readCharset()), Charset.cp1252);
    });
  });
}
