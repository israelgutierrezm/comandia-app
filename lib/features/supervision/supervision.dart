import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/token_storage.dart';

Map<String, dynamic> _unwrap(dynamic body) {
  if (body is Map && body['data'] is Map) return Map<String, dynamic>.from(body['data'] as Map);
  return Map<String, dynamic>.from(body as Map);
}

class AppContext {
  AppContext({
    required this.tenantName,
    required this.membershipName,
    required this.roleUlid,
    required this.roleName,
    required this.branchUlid,
    required this.branchName,
    required this.isReadOnly,
    required this.permissionsCount,
  });

  final String tenantName;
  final String? membershipName;
  final String? roleUlid;
  final String? roleName;
  final String? branchUlid;
  final String? branchName;
  final bool isReadOnly;
  final int permissionsCount;

  factory AppContext.fromJson(Map<String, dynamic> d) {
    final branches = (d['branches'] as List?) ?? const [];
    final activeBranch = d['active_branch'] as Map?;
    // Si no hay sucursal activa (recién iniciada la sesión), se toma la primera alcanzable.
    final branch = activeBranch ?? (branches.isNotEmpty ? branches.first as Map : null);

    return AppContext(
      tenantName: (d['tenant']?['name'] ?? '—') as String,
      membershipName: d['membership']?['display_name'] as String?,
      roleUlid: d['active_role']?['ulid'] as String?,
      roleName: d['active_role']?['name'] as String?,
      branchUlid: branch?['ulid'] as String?,
      branchName: branch?['name'] as String?,
      isReadOnly: (d['is_read_only'] ?? false) as bool,
      permissionsCount: ((d['permissions'] as List?) ?? const []).length,
    );
  }
}

class OpenSession {
  OpenSession({required this.ulid, required this.folio, this.terminalName, this.branchName, this.openedAt});

  final String ulid;
  final String folio;
  final String? terminalName;
  final String? branchName;
  final String? openedAt;

  factory OpenSession.fromJson(Map<String, dynamic> d) => OpenSession(
        ulid: d['ulid'] as String,
        folio: (d['folio'] ?? '—') as String,
        terminalName: d['terminal']?['name'] as String?,
        branchName: d['branch']?['name'] as String?,
        openedAt: d['opened_at'] as String?,
      );
}

class CutMethod {
  CutMethod({required this.method, this.expected, this.declared, this.difference});

  final String method;
  final String? expected;
  final String? declared;
  final String? difference;

  factory CutMethod.fromJson(Map<String, dynamic> d) => CutMethod(
        method: (d['method'] ?? '—') as String,
        expected: d['expected'] as String?,
        declared: d['declared'] as String?,
        difference: d['difference'] as String?,
      );
}

class SupervisionData {
  SupervisionData({required this.context, this.session, this.cut = const [], this.cutForbidden = false});

  final AppContext context;
  final OpenSession? session;
  final List<CutMethod> cut;
  final bool cutForbidden;
}

class SupervisionRepository {
  SupervisionRepository(this._api, this._storage);

  final ApiClient _api;
  final TokenStorage _storage;

  Future<SupervisionData> load() async {
    // 1) El contexto: quién soy, con qué rol y en qué sucursal. Con sólo el token basta (usa el rol por omisión).
    final ctxRes = await _api.dio.get<dynamic>('/context');
    if (ctxRes.statusCode != 200) {
      throw Exception('No se pudo cargar el contexto (${ctxRes.statusCode}).');
    }
    final context = AppContext.fromJson(_unwrap(ctxRes.data));

    // Se guardan el rol y la sucursal activos para que viajen como cabeceras en lo que sigue.
    await _storage.saveContext(roleUlid: context.roleUlid, branchUlid: context.branchUlid);

    // 2) La caja abierta de la sucursal (si hay).
    OpenSession? session;
    final sesRes = await _api.dio.get<dynamic>('/pos-sessions', queryParameters: {'status': 'open', 'per_page': 20});
    if (sesRes.statusCode == 200) {
      final list = (sesRes.data is Map ? sesRes.data['data'] : sesRes.data) as List? ?? const [];
      Map<String, dynamic>? match;
      for (final raw in list) {
        final s = Map<String, dynamic>.from(raw as Map);
        if (context.branchUlid == null || s['branch']?['ulid'] == context.branchUlid) {
          match = s;
          break;
        }
      }
      match ??= list.isNotEmpty ? Map<String, dynamic>.from(list.first as Map) : null;
      if (match != null) session = OpenSession.fromJson(match);
    }

    // 3) El corte del turno, si esta persona puede verlo (el precorte ciego, D289: un 403 no es un error).
    var cut = <CutMethod>[];
    var cutForbidden = false;
    if (session != null) {
      final cutRes = await _api.dio.get<dynamic>('/pos-sessions/${session.ulid}/cut');
      if (cutRes.statusCode == 200) {
        final d = _unwrap(cutRes.data);
        cut = ((d['by_method'] as List?) ?? const [])
            .map((m) => CutMethod.fromJson(Map<String, dynamic>.from(m as Map)))
            .toList();
      } else if (cutRes.statusCode == 403) {
        cutForbidden = true;
      }
    }

    return SupervisionData(context: context, session: session, cut: cut, cutForbidden: cutForbidden);
  }
}

final supervisionRepositoryProvider = Provider<SupervisionRepository>(
  (ref) => SupervisionRepository(ref.watch(apiClientProvider), ref.watch(tokenStorageProvider)),
);

class SupervisionController extends AsyncNotifier<SupervisionData> {
  @override
  Future<SupervisionData> build() => ref.read(supervisionRepositoryProvider).load();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(supervisionRepositoryProvider).load());
  }
}

final supervisionControllerProvider =
    AsyncNotifierProvider<SupervisionController, SupervisionData>(SupervisionController.new);
