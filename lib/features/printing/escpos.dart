import 'dart:convert';

/// Constructor mínimo de comandos ESC/POS (impresoras térmicas).
///
/// v1: el texto se normaliza a ASCII (los acentos se pliegan: á→a, ñ→n) para evitar caracteres corruptos por diferencias
/// de página de códigos entre modelos. El soporte de página de códigos completa es evolución natural.
class EscPos {
  final List<int> _b = [];

  static const int _esc = 0x1B;
  static const int _gs = 0x1D;
  static const int _lf = 0x0A;

  EscPos() {
    _b.addAll([_esc, 0x40]); // inicializar
  }

  /// 0 izquierda, 1 centro, 2 derecha.
  void align(int a) => _b.addAll([_esc, 0x61, a]);

  void bold(bool on) => _b.addAll([_esc, 0x45, on ? 1 : 0]);

  /// Ancho y alto de 1 a 8.
  void size(int w, int h) => _b.addAll([_gs, 0x21, ((w - 1) << 4) | (h - 1)]);

  void text(String s) => _b.addAll(_encode(s));

  void line([String s = '']) {
    text(s);
    _b.add(_lf);
  }

  void feed([int n = 1]) => _b.addAll(List.filled(n, _lf));

  /// Corte total del papel.
  void cut() => _b.addAll([_gs, 0x56, 0x00]);

  /// Pulso al cajón de dinero.
  void drawer() => _b.addAll([_esc, 0x70, 0x00, 0x19, 0xFA]);

  List<int> bytes() => List.unmodifiable(_b);

  List<int> _encode(String s) => latin1.encode(_fold(s));

  static String _fold(String s) {
    const map = {
      'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'Á': 'A', 'À': 'A', 'Ä': 'A', 'Â': 'A',
      'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e', 'É': 'E', 'È': 'E', 'Ë': 'E', 'Ê': 'E',
      'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i', 'Í': 'I', 'Ì': 'I', 'Ï': 'I', 'Î': 'I',
      'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'Ó': 'O', 'Ò': 'O', 'Ö': 'O', 'Ô': 'O',
      'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u', 'Ú': 'U', 'Ù': 'U', 'Ü': 'U', 'Û': 'U',
      'ñ': 'n', 'Ñ': 'N', '¿': '?', '¡': '!', '€': 'EUR',
    };
    final sb = StringBuffer();
    for (final ch in s.split('')) {
      sb.write(map[ch] ?? (ch.codeUnitAt(0) < 128 ? ch : '?'));
    }
    return sb.toString();
  }
}

String _money(dynamic v) => v == null ? '' : '\$$v';

/// Una fila con etiqueta a la izquierda e importe a la derecha, alineados al ancho.
String _row(String left, String right, int cols) {
  if (left.length + right.length + 1 > cols) {
    left = left.substring(0, (cols - right.length - 1).clamp(0, left.length));
  }
  final gap = (cols - left.length - right.length).clamp(1, cols);
  return left + ' ' * gap + right;
}

/// Renderiza el payload estructurado del ticket (contrato v1) a bytes ESC/POS.
///
/// Sirve para comanda (sin dinero) y ticket final (con totales y pagos): la presencia de `totals` distingue uno de otro.
List<int> renderTicket(Map<String, dynamic> payload, {int? paperWidth}) {
  // El ancho del papel llega en milímetros (58/80); a caracteres son ~32/48 con la fuente por defecto.
  final cols = (paperWidth != null && paperWidth <= 58) ? 32 : 48;
  final p = EscPos();

  p.align(1);
  p.bold(true);
  p.size(2, 2);
  p.line('${payload['business']?['name'] ?? 'Comandia'}');
  p.size(1, 1);
  if (payload['kind_label'] != null) p.line('${payload['kind_label']}');
  p.bold(false);
  p.align(0);
  p.feed();

  final account = payload['account'];
  if (account?['display_name'] != null) p.line('${account['display_name']}');
  if (payload['folio'] != null) p.line('Folio: ${payload['folio']}');
  if (payload['area'] != null) p.line('Area: ${payload['area']}');
  if (payload['order_sequence'] != null) p.line('Orden: ${payload['order_sequence']}');
  p.line('-' * cols);

  final totals = payload['totals'] as Map?;
  final isReceipt = totals != null;

  for (final raw in (payload['items'] as List? ?? const [])) {
    final it = Map<String, dynamic>.from(raw as Map);
    final head = '${it['quantity']} x ${it['name'] ?? ''}';
    if (isReceipt) {
      p.line(_row(head, _money(it['line_total']), cols));
    } else {
      p.bold(true);
      p.line(head);
      p.bold(false);
    }
    for (final m in (it['modifiers'] as List? ?? const [])) {
      p.line('   + ${m['name']}');
    }
  }

  if (isReceipt) {
    p.line('-' * cols);
    p.line(_row('Subtotal', _money(totals['subtotal']), cols));
    if (totals['discount_total'] != null) p.line(_row('Descuentos', _money(totals['discount_total']), cols));
    p.line(_row('IVA incluido', _money(totals['vat_total']), cols));
    p.bold(true);
    p.line(_row('Total', _money(totals['total']), cols));
    p.bold(false);
    for (final raw in (payload['payments'] as List? ?? const [])) {
      final pay = Map<String, dynamic>.from(raw as Map);
      p.line(_row('${pay['method'] ?? 'Pago'}', _money(pay['amount']), cols));
    }
    final change = totals['change_total'];
    if (change != null && change != '0.00') p.line(_row('Cambio', _money(change), cols));
  }

  p.feed(3);
  p.cut();
  return p.bytes();
}
