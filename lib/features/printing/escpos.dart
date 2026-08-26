import 'dart:convert';

/// Página de códigos con la que la impresora interpreta los bytes de texto.
///
/// No hay una universal: los modelos numeran distinto. Por eso es configurable, con un valor de fábrica (CP850) que
/// funciona en la mayoría de las térmicas genéricas, y ASCII como red de seguridad (nunca imprime basura).
enum Charset {
  /// Plegado a ASCII (á→a, ñ→n). No manda `ESC t`; sirve en cualquier impresora.
  ascii('ASCII', []),

  /// PC850 Multilingüe (Latin-1). `ESC t 2`.
  cp850('CP850', [0x1B, 0x74, 0x02]),

  /// Windows-1252 (WPC1252), típico de Epson. `ESC t 16`.
  cp1252('CP1252', [0x1B, 0x74, 0x10]);

  const Charset(this.label, this.selector);

  /// Etiqueta para la interfaz.
  final String label;

  /// Bytes que seleccionan la página en la impresora (`ESC t n`); vacío en ASCII.
  final List<int> selector;

  static Charset fromName(String? name) =>
      Charset.values.firstWhere((c) => c.name == name, orElse: () => Charset.cp850);

  /// Codifica el texto a bytes según la página. Los caracteres fuera de la página se pliegan a ASCII para no romper.
  List<int> encode(String s) {
    switch (this) {
      case Charset.ascii:
        return latin1.encode(_foldAscii(s));
      // CP1252 coincide con Latin-1 en 0xA0–0xFF, donde viven todos los acentos del español: el code unit ES el byte.
      case Charset.cp1252:
        return _mapped(s, (cu) => cu <= 0xFF ? cu : null);
      case Charset.cp850:
        return _mapped(s, (cu) => cu < 0x80 ? cu : _cp850[cu]);
    }
  }

  List<int> _mapped(String s, int? Function(int codeUnit) map) {
    final out = <int>[];
    for (final ch in s.split('')) {
      final b = map(ch.codeUnitAt(0));
      if (b != null) {
        out.add(b);
      } else {
        // Fuera de la página: se pliega ese carácter a ASCII (á→a, €→EUR) antes que imprimir un byte al azar.
        out.addAll(latin1.encode(_foldAscii(ch)));
      }
    }
    return out;
  }
}

/// Unicode → byte en CP850, para el conjunto del español mexicano. Lo de fuera se pliega.
const Map<int, int> _cp850 = {
  0xE1: 0xA0, // á
  0xE9: 0x82, // é
  0xED: 0xA1, // í
  0xF3: 0xA2, // ó
  0xFA: 0xA3, // ú
  0xF1: 0xA4, // ñ
  0xD1: 0xA5, // Ñ
  0xFC: 0x81, // ü
  0xDC: 0x9A, // Ü
  0xC1: 0xB5, // Á
  0xC9: 0x90, // É
  0xCD: 0xD6, // Í
  0xD3: 0xE0, // Ó
  0xDA: 0xE9, // Ú
  0xBF: 0xA8, // ¿
  0xA1: 0xAD, // ¡
  0xB0: 0xF8, // °
};

String _foldAscii(String s) {
  const map = {
    'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'Á': 'A', 'À': 'A', 'Ä': 'A', 'Â': 'A',
    'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e', 'É': 'E', 'È': 'E', 'Ë': 'E', 'Ê': 'E',
    'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i', 'Í': 'I', 'Ì': 'I', 'Ï': 'I', 'Î': 'I',
    'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'Ó': 'O', 'Ò': 'O', 'Ö': 'O', 'Ô': 'O',
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u', 'Ú': 'U', 'Ù': 'U', 'Ü': 'U', 'Û': 'U',
    'ñ': 'n', 'Ñ': 'N', '¿': '?', '¡': '!', '€': 'EUR', '°': ' ',
  };
  final sb = StringBuffer();
  for (final ch in s.split('')) {
    sb.write(map[ch] ?? (ch.codeUnitAt(0) < 128 ? ch : '?'));
  }
  return sb.toString();
}

/// Constructor mínimo de comandos ESC/POS (impresoras térmicas).
class EscPos {
  EscPos({this.charset = Charset.cp850}) {
    _b.addAll([_esc, 0x40]); // inicializar
    _b.addAll(charset.selector); // ESC t n — la página de códigos
  }

  final Charset charset;
  final List<int> _b = [];

  static const int _esc = 0x1B;
  static const int _gs = 0x1D;
  static const int _lf = 0x0A;

  /// 0 izquierda, 1 centro, 2 derecha.
  void align(int a) => _b.addAll([_esc, 0x61, a]);

  void bold(bool on) => _b.addAll([_esc, 0x45, on ? 1 : 0]);

  /// Ancho y alto de 1 a 8.
  void size(int w, int h) => _b.addAll([_gs, 0x21, ((w - 1) << 4) | (h - 1)]);

  void text(String s) => _b.addAll(charset.encode(s));

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
List<int> renderTicket(Map<String, dynamic> payload, {int? paperWidth, Charset charset = Charset.cp850}) {
  // El ancho del papel llega en milímetros (58/80); a caracteres son ~32/48 con la fuente por defecto.
  final cols = (paperWidth != null && paperWidth <= 58) ? 32 : 48;
  final p = EscPos(charset: charset);

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
  if (payload['area'] != null) p.line('Área: ${payload['area']}');
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
