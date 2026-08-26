import 'dart:convert';

import 'package:comandia_app/features/printing/escpos.dart';
import 'package:comandia_app/features/printing/print_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

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
    });

    final text = latin1.decode(bytes);
    expect(text, contains('Cocina'));
    expect(text, contains('Mesa 4'));
    expect(text, contains('Barra'));
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
    });

    final text = latin1.decode(bytes);
    expect(text, contains('Subtotal'));
    expect(text, contains('IVA incluido'));
    expect(text, contains('Total'));
    expect(text, contains('\$90.00'));
    expect(text, contains('Efectivo'));
    expect(text, contains('Cambio'));
  });

  test('el texto se normaliza a ASCII: sin bytes altos por acentos', () {
    final bytes = renderTicket({
      'business': {'name': 'Café Ñandú'},
      'account': {'display_name': 'Órdenes'},
      'items': const [],
    });

    final text = latin1.decode(bytes);
    expect(text, contains('Cafe Nandu'));
    expect(text, contains('Ordenes'));
    // Ningún byte de texto imprimible por encima de 126 (los acentos se plegaron, no se codificaron crudos).
    expect(bytes.where((b) => b > 126 && b < 160), isEmpty);
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
}
