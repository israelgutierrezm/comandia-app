import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/token_storage.dart';
import '../supervision/supervision.dart' show CutMethod;

/// Un turno de caja en el listado.
class SessionSummary {
  SessionSummary({
    required this.ulid,
    required this.folio,
    required this.status,
    required this.statusLabel,
    this.terminalName,
    this.openedAt,
    this.closedAt,
  });

  final String ulid;
  final String folio;
  final String status;
  final String statusLabel;
  final String? terminalName;
  final String? openedAt;
  final String? closedAt;

  factory SessionSummary.fromJson(Map<String, dynamic> d) => SessionSummary(
        ulid: d['ulid'] as String,
        folio: (d['folio'] ?? '—') as String,
        status: (d['status'] ?? '') as String,
        statusLabel: (d['status_label'] ?? d['status'] ?? '—') as String,
        terminalName: d['terminal']?['name'] as String?,
        openedAt: d['opened_at'] as String?,
        closedAt: d['closed_at'] as String?,
      );
}

/// Una terminal (caja física) de la sucursal, para abrir un turno en ella.
class Terminal {
  Terminal({required this.ulid, required this.name, this.branchName});

  final String ulid;
  final String name;
  final String? branchName;

  factory Terminal.fromJson(Map<String, dynamic> d) => Terminal(
        ulid: d['ulid'] as String,
        name: (d['name'] ?? '—') as String,
        branchName: (d['branch'] as Map?)?['name'] as String?,
      );
}

/// El servidor rechazó una operación de caja (validación, estado); lleva su mensaje para mostrarlo tal cual.
class CajaError implements Exception {
  const CajaError(this.message);
  final String message;
  @override
  String toString() => message;
}

class SessionsRepository {
  SessionsRepository(this._api, this._storage);

  final ApiClient _api;
  final TokenStorage _storage;

  Future<List<SessionSummary>> list({required String status}) async {
    final res = await _api.dio.get<dynamic>('/pos-sessions', queryParameters: {
      'status': status,
      'per_page': 50,
      'sort': '-opened_at',
    });
    if (res.statusCode != 200) {
      throw Exception('No se pudieron cargar los turnos (${res.statusCode}).');
    }
    final list = (res.data is Map ? res.data['data'] : res.data) as List? ?? const [];
    return list.map((e) => SessionSummary.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<List<CutMethod>> cut(String sessionUlid) async {
    final res = await _api.dio.get<dynamic>('/pos-sessions/$sessionUlid/cut');
    if (res.statusCode == 403) {
      throw const CutForbidden();
    }
    if (res.statusCode != 200) {
      throw Exception('No se pudo cargar el corte (${res.statusCode}).');
    }
    final d = (res.data is Map ? res.data['data'] : res.data) as Map;
    return ((d['by_method'] as List?) ?? const [])
        .map((m) => CutMethod.fromJson(Map<String, dynamic>.from(m as Map)))
        .toList();
  }

  /// Las terminales activas de la sucursal activa. Necesita `organization.terminals.view` (gerente/propietario).
  Future<List<Terminal>> terminals() async {
    final branch = await _storage.readBranch();
    final res = await _api.dio.get<dynamic>('/terminals', queryParameters: {
      'status': 'active',
      'per_page': 50,
      'branch': ?branch,
    });
    if (res.statusCode != 200) throw CajaError('No se pudieron cargar las terminales (${res.statusCode}).');
    final list = (res.data is Map ? res.data['data'] : res.data) as List? ?? const [];
    return list.map((e) => Terminal.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<void> openSession(String terminalUlid, String openingFloat) => _post('/pos-sessions', {
        'terminal_ulid': terminalUlid,
        'opening_float': openingFloat,
      });

  /// Declara el efectivo contado por método. `moment` es 'precount' (arqueo) o 'close' (antes de cerrar).
  Future<void> declare(String ulid, String moment, List<Map<String, String>> declarations) =>
      _post('/pos-sessions/$ulid/declarations', {'moment': moment, 'declarations': declarations});

  Future<void> closeSession(String ulid, {String? notes}) => _post('/pos-sessions/$ulid/close', {'notes': ?notes});

  Future<void> _post(String path, Map<String, dynamic> data) async {
    final res = await _api.dio.post<dynamic>(path, data: data);
    if (res.statusCode == 200 || res.statusCode == 201) return;
    final msg = (res.data is Map ? res.data['message'] : null) as String?;
    throw CajaError(msg ?? 'La operación de caja falló (${res.statusCode}).');
  }
}

/// El precorte ciego (D289): ver el corte es un permiso aparte; un 403 no es un error.
class CutForbidden implements Exception {
  const CutForbidden();
}

final sessionsRepositoryProvider = Provider<SessionsRepository>(
  (ref) => SessionsRepository(ref.watch(apiClientProvider), ref.watch(tokenStorageProvider)),
);

final terminalsProvider = FutureProvider.autoDispose<List<Terminal>>(
  (ref) => ref.watch(sessionsRepositoryProvider).terminals(),
);

/// El estado seleccionado en la pestaña de turnos.
final sessionsFilterProvider = StateProvider<String>((ref) => 'open');

final sessionsListProvider =
    FutureProvider.autoDispose.family<List<SessionSummary>, String>((ref, status) {
  return ref.watch(sessionsRepositoryProvider).list(status: status);
});

final sessionCutProvider =
    FutureProvider.autoDispose.family<List<CutMethod>, String>((ref, ulid) {
  return ref.watch(sessionsRepositoryProvider).cut(ulid);
});
