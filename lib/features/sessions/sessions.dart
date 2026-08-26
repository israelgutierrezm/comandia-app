import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
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

class SessionsRepository {
  SessionsRepository(this._api);

  final ApiClient _api;

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
}

/// El precorte ciego (D289): ver el corte es un permiso aparte; un 403 no es un error.
class CutForbidden implements Exception {
  const CutForbidden();
}

final sessionsRepositoryProvider = Provider<SessionsRepository>(
  (ref) => SessionsRepository(ref.watch(apiClientProvider)),
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
