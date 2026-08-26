import 'package:comandia_app/features/pos/pos.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Account.fromJson lee items, totales y órdenes', () {
    final a = Account.fromJson({
      'ulid': 'ACC1',
      'display_name': 'Mesa 4',
      'folio': 'A-0001',
      'status_label': 'Abierta',
      'version': 3,
      'accepts_items': true,
      'totals': {'subtotal': '100.00', 'total': '100.00', 'due': '100.00'},
      'items': [
        {'ulid': 'I1', 'quantity': 2, 'article_name': 'Taco', 'line_total': '40.00', 'status': 'captured', 'order_ulid': 'O1'},
      ],
      'orders': [
        {'ulid': 'O1', 'sequence': 1},
      ],
    });

    expect(a.version, 3);
    expect(a.acceptsItems, isTrue);
    expect(a.totals['total'], '100.00');
    expect(a.items.single.captured, isTrue);
    expect(a.items.single.orderUlid, 'O1');
    expect(a.orders.single.sequence, 1);
  });

  test('CatalogArticle.fromJson usa display_name y categoría', () {
    final c = CatalogArticle.fromJson({
      'ulid': 'ART1',
      'display_name': 'Enchiladas',
      'base_price': '145.00',
      'category': {'ulid': 'CAT1', 'name': 'Fuertes'},
    });
    expect(c.name, 'Enchiladas');
    expect(c.categoryName, 'Fuertes');
  });

  test('carrito de captura: sumar, incrementar y quitar', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(captureCartProvider('ACC1').notifier);
    final taco = CatalogArticle(ulid: 'ART1', name: 'Taco', basePrice: '20.00');
    final agua = CatalogArticle(ulid: 'ART2', name: 'Agua', basePrice: '25.00');

    notifier.add(taco);
    notifier.add(taco);
    notifier.add(agua);

    var lines = container.read(captureCartProvider('ACC1'));
    expect(lines.length, 2);
    expect(lines.firstWhere((l) => l.articleUlid == 'ART1').quantity, 2);
    expect(notifier.count, 3);

    // Bajar el taco a cero lo quita de la lista.
    notifier.dec('ART1');
    notifier.dec('ART1');
    lines = container.read(captureCartProvider('ACC1'));
    expect(lines.any((l) => l.articleUlid == 'ART1'), isFalse);
    expect(lines.length, 1);
  });
}
