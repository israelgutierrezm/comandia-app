import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/token_storage.dart';

// ---------------------------------------------------------------------------
// Modelos
// ---------------------------------------------------------------------------

class CatalogArticle {
  CatalogArticle({required this.ulid, required this.name, this.basePrice, this.categoryUlid, this.categoryName});

  final String ulid;
  final String name;
  final String? basePrice;
  final String? categoryUlid;
  final String? categoryName;

  factory CatalogArticle.fromJson(Map<String, dynamic> d) => CatalogArticle(
        ulid: d['ulid'] as String,
        name: (d['display_name'] ?? d['name'] ?? '—') as String,
        basePrice: d['base_price'] as String?,
        categoryUlid: d['category']?['ulid'] as String?,
        categoryName: d['category']?['name'] as String?,
      );
}

class AccountSummary {
  AccountSummary({required this.ulid, required this.displayName, required this.folio, required this.statusLabel, this.total, this.due});

  final String ulid;
  final String displayName;
  final String folio;
  final String statusLabel;
  final String? total;
  final String? due;

  factory AccountSummary.fromJson(Map<String, dynamic> d) => AccountSummary(
        ulid: d['ulid'] as String,
        displayName: (d['display_name'] ?? '—') as String,
        folio: (d['folio'] ?? '—') as String,
        statusLabel: (d['status_label'] ?? '—') as String,
        total: d['totals']?['total'] as String?,
        due: d['totals']?['due'] as String?,
      );
}

class AccountItem {
  AccountItem({
    required this.quantity,
    required this.articleName,
    this.unitPrice,
    this.lineTotal,
    this.statusLabel,
    this.orderUlid,
    this.isCourtesy = false,
    this.cancelled = false,
    this.captured = false,
  });

  final String quantity;
  final String articleName;
  final String? unitPrice;
  final String? lineTotal;
  final String? statusLabel;
  final String? orderUlid;
  final bool isCourtesy;
  final bool cancelled;
  final bool captured;

  factory AccountItem.fromJson(Map<String, dynamic> d) => AccountItem(
        quantity: '${d['quantity'] ?? ''}',
        articleName: (d['article_name'] ?? '—') as String,
        unitPrice: d['unit_price'] as String?,
        lineTotal: d['line_total'] as String?,
        statusLabel: d['status_label'] as String?,
        orderUlid: d['order_ulid'] as String?,
        isCourtesy: (d['is_courtesy'] ?? false) as bool,
        cancelled: d['status'] == 'cancelled',
        captured: d['status'] == 'captured',
      );
}

class AccountOrder {
  AccountOrder(this.ulid, this.sequence);
  final String ulid;
  final int sequence;
}

class Account {
  Account({
    required this.ulid,
    required this.displayName,
    required this.folio,
    required this.statusLabel,
    required this.version,
    required this.acceptsItems,
    required this.totals,
    required this.items,
    required this.orders,
  });

  final String ulid;
  final String displayName;
  final String folio;
  final String statusLabel;
  final dynamic version;
  final bool acceptsItems;
  final Map<String, String?> totals;
  final List<AccountItem> items;
  final List<AccountOrder> orders;

  factory Account.fromJson(Map<String, dynamic> d) {
    final t = (d['totals'] as Map?) ?? const {};
    return Account(
      ulid: d['ulid'] as String,
      displayName: (d['display_name'] ?? '—') as String,
      folio: (d['folio'] ?? '—') as String,
      statusLabel: (d['status_label'] ?? '—') as String,
      version: d['version'],
      acceptsItems: (d['accepts_items'] ?? false) as bool,
      totals: {
        for (final k in ['subtotal', 'discount_total', 'vat_total', 'total', 'paid_total', 'due', 'change_total', 'tip_total'])
          k: t[k] as String?,
      },
      items: ((d['items'] as List?) ?? const [])
          .map((e) => AccountItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      orders: ((d['orders'] as List?) ?? const [])
          .map((e) => AccountOrder(e['ulid'] as String, (e['sequence'] ?? 0) as int))
          .toList(),
    );
  }
}

/// Una línea del carrito LOCAL de captura (aún no enviada). Al capturar sólo viaja ulid + cantidad; el precio es de
/// referencia y lo congela el servidor.
class CaptureLine {
  CaptureLine({required this.articleUlid, required this.name, required this.quantity, this.price});
  final String articleUlid;
  final String name;
  final String? price;
  final int quantity;

  CaptureLine copyWith({int? quantity}) =>
      CaptureLine(articleUlid: articleUlid, name: name, price: price, quantity: quantity ?? this.quantity);
}

/// Un método de pago del catálogo. Las tres banderas las resuelve el servidor y dicen a la caja cómo comportarse: si
/// calcular cambio, si exigir referencia y si el método toca el cajón de efectivo.
class PaymentMethod {
  PaymentMethod({
    required this.ulid,
    required this.name,
    required this.allowsChange,
    required this.requiresReference,
    required this.affectsCashDrawer,
  });

  final String ulid;
  final String name;
  final bool allowsChange;
  final bool requiresReference;
  final bool affectsCashDrawer;

  factory PaymentMethod.fromJson(Map<String, dynamic> d) => PaymentMethod(
        ulid: d['ulid'] as String,
        name: (d['name'] ?? '—') as String,
        allowsChange: (d['allows_change'] ?? false) as bool,
        requiresReference: (d['requires_reference'] ?? false) as bool,
        affectsCashDrawer: (d['affects_cash_drawer'] ?? false) as bool,
      );
}

/// Una línea de pago que se está armando en la caja. Los montos viajan como texto decimal (2 posiciones), como el resto
/// del dinero. `tendered` (recibido) solo tiene sentido en efectivo; el servidor calcula el cambio.
class PaymentLine {
  PaymentLine({required this.method, required this.amount, this.tendered, this.tip, this.reference});

  final PaymentMethod method;
  final String amount;
  final String? tendered;
  final String? tip;
  final String? reference;

  Map<String, dynamic> toJson() => {
        'payment_method_ulid': method.ulid,
        'amount': amount,
        if (tendered != null && tendered!.isNotEmpty) 'tendered_amount': tendered,
        if (tip != null && tip!.isNotEmpty) 'tip_amount': tip,
        if (reference != null && reference!.isNotEmpty) 'reference': reference,
      };
}

/// El servidor rechazó el cobro (422): monto inválido, referencia faltante, etc. Lleva su mensaje para mostrarlo tal cual.
class ChargeError implements Exception {
  const ChargeError(this.message);
  final String message;
  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Repositorio
// ---------------------------------------------------------------------------

class PosRepository {
  PosRepository(this._api, this._storage);

  final ApiClient _api;
  final TokenStorage _storage;

  Future<List<AccountSummary>> openAccounts() async {
    final res = await _api.dio.get<dynamic>('/pos-accounts', queryParameters: {'only_open': 1, 'per_page': 50});
    _ok(res.statusCode, 'las cuentas');
    return _list(res.data).map((e) => AccountSummary.fromJson(e)).toList();
  }

  /// Abre una cuenta PARA LLEVAR en la sucursal activa (el número de mostrador lo asigna el servidor). Es la vía
  /// rápida de esta versión; abrir en mesa o de barra llegará con el selector correspondiente.
  Future<AccountSummary> openTakeout() async {
    final branch = await _storage.readBranch();
    final res = await _api.dio.post<dynamic>('/pos-accounts', data: {'branch_ulid': branch, 'takeout': true});
    _created(res.statusCode, 'abrir la cuenta');
    return AccountSummary.fromJson(_map(res.data));
  }

  Future<List<CatalogArticle>> catalog() async {
    final res = await _api.dio.get<dynamic>('/articles', queryParameters: {
      'available_in_pos': 1,
      'status': 'active',
      'per_page': 200,
    });
    _ok(res.statusCode, 'el catálogo');
    return _list(res.data).map((e) => CatalogArticle.fromJson(e)).toList();
  }

  Future<Account> account(String ulid) async {
    final res = await _api.dio.get<dynamic>('/pos-accounts/$ulid');
    _ok(res.statusCode, 'la cuenta');
    return Account.fromJson(_map(res.data));
  }

  /// Captura líneas; el servidor congela el precio y devuelve la cuenta completa.
  Future<Account> capture(String ulid, dynamic version, List<CaptureLine> lines) async {
    final res = await _api.dio.post<dynamic>('/pos-accounts/$ulid/orders', data: {
      'version': version,
      'lines': [
        for (final l in lines) {'article_ulid': l.articleUlid, 'quantity': '${l.quantity}'},
      ],
    });
    if (res.statusCode == 409) throw const StaleAccount();
    _created(res.statusCode, 'capturar');
    return Account.fromJson(_map(res.data));
  }

  Future<void> command(String ulid, String orderUlid, dynamic version) async {
    final res = await _api.dio.post<dynamic>('/pos-accounts/$ulid/orders/$orderUlid/command', data: {'version': version});
    if (res.statusCode == 409) throw const StaleAccount();
    _created(res.statusCode, 'comandar');
  }

  Future<List<PaymentMethod>> paymentMethods() async {
    final res = await _api.dio.get<dynamic>('/payment-methods', queryParameters: {'status': 'active', 'per_page': 100});
    _ok(res.statusCode, 'los métodos de pago');
    return _list(res.data).map((e) => PaymentMethod.fromJson(e)).toList();
  }

  /// Cobra la cuenta con uno o varios pagos. Cuando lo pagado cubre el total, el servidor la pasa a `paid` y emite el
  /// ticket final (que imprime por el puente). Devuelve la cuenta actualizada (con `change_total` si hubo cambio).
  Future<Account> charge(String ulid, dynamic version, List<PaymentLine> payments) async {
    final res = await _api.dio.post<dynamic>('/pos-accounts/$ulid/payments', data: {
      'version': version,
      'payments': [for (final p in payments) p.toJson()],
    });
    if (res.statusCode == 409) throw const StaleAccount();
    if (res.statusCode == 422) {
      final msg = (res.data is Map ? res.data['message'] : null) as String?;
      throw ChargeError(msg ?? 'No se pudo cobrar: revisa los montos.');
    }
    _created(res.statusCode, 'cobrar');
    return Account.fromJson(_map(res.data));
  }

  List<Map<String, dynamic>> _list(dynamic body) {
    final raw = (body is Map ? body['data'] : body) as List? ?? const [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Map<String, dynamic> _map(dynamic body) =>
      Map<String, dynamic>.from((body is Map && body['data'] is Map ? body['data'] : body) as Map);

  void _ok(int? status, String what) {
    if (status != 200) throw Exception('No se pudo cargar $what ($status).');
  }

  void _created(int? status, String what) {
    if (status != 200 && status != 201) throw Exception('No se pudo $what ($status).');
  }
}

/// El candado optimista: otra terminal tocó la cuenta; hay que recargar.
class StaleAccount implements Exception {
  const StaleAccount();
}

final posRepositoryProvider = Provider<PosRepository>(
  (ref) => PosRepository(ref.watch(apiClientProvider), ref.watch(tokenStorageProvider)),
);

final openAccountsProvider = FutureProvider.autoDispose<List<AccountSummary>>(
  (ref) => ref.watch(posRepositoryProvider).openAccounts(),
);

final catalogProvider = FutureProvider.autoDispose<List<CatalogArticle>>(
  (ref) => ref.watch(posRepositoryProvider).catalog(),
);

final accountProvider = FutureProvider.autoDispose.family<Account, String>(
  (ref, ulid) => ref.watch(posRepositoryProvider).account(ulid),
);

final paymentMethodsProvider = FutureProvider.autoDispose<List<PaymentMethod>>(
  (ref) => ref.watch(posRepositoryProvider).paymentMethods(),
);

/// Los permisos del rol activo, leídos del contexto. Sirven para ocultar acciones que el servidor rechazaría de todos
/// modos (p. ej. «Cobrar» a un mesero sin `pos.accounts.charge`). El servidor sigue siendo la autoridad.
final permissionsProvider = FutureProvider<Set<String>>((ref) async {
  final res = await ref.watch(apiClientProvider).dio.get<dynamic>('/context');
  final data = (res.data is Map && res.data['data'] is Map) ? res.data['data'] as Map : (res.data as Map);
  return ((data['permissions'] as List?) ?? const []).map((e) => '$e').toSet();
});

// ---------------------------------------------------------------------------
// Carrito de captura (local, por cuenta)
// ---------------------------------------------------------------------------

class CaptureCart extends FamilyNotifier<List<CaptureLine>, String> {
  @override
  List<CaptureLine> build(String arg) => const [];

  void add(CatalogArticle article) {
    final existing = state.indexWhere((l) => l.articleUlid == article.ulid);
    if (existing >= 0) {
      final copy = [...state];
      copy[existing] = copy[existing].copyWith(quantity: copy[existing].quantity + 1);
      state = copy;
    } else {
      state = [
        ...state,
        CaptureLine(articleUlid: article.ulid, name: article.name, price: article.basePrice, quantity: 1),
      ];
    }
  }

  void inc(String ulid) => _update(ulid, (l) => l.copyWith(quantity: l.quantity + 1));

  void dec(String ulid) {
    final line = state.firstWhere((l) => l.articleUlid == ulid);
    if (line.quantity <= 1) {
      remove(ulid);
    } else {
      _update(ulid, (l) => l.copyWith(quantity: l.quantity - 1));
    }
  }

  void remove(String ulid) => state = state.where((l) => l.articleUlid != ulid).toList();

  void clear() => state = const [];

  int get count => state.fold(0, (sum, l) => sum + l.quantity);

  void _update(String ulid, CaptureLine Function(CaptureLine) f) =>
      state = [for (final l in state) if (l.articleUlid == ulid) f(l) else l];
}

final captureCartProvider = NotifierProvider.family<CaptureCart, List<CaptureLine>, String>(CaptureCart.new);
