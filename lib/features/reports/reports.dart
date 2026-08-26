import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';

class ReportSummary {
  ReportSummary(this.key, this.label);
  final String key;
  final String label;
}

class ReportColumn {
  ReportColumn(this.key, this.label);
  final String key;
  final String label;
}

class ReportData {
  ReportData({required this.columns, required this.rows});
  final List<ReportColumn> columns;
  final List<Map<String, dynamic>> rows;
}

class ReportsRepository {
  ReportsRepository(this._api);

  final ApiClient _api;

  Future<List<ReportSummary>> list() async {
    final res = await _api.dio.get<dynamic>('/reports');
    if (res.statusCode != 200) {
      throw Exception('No se pudieron cargar los reportes (${res.statusCode}).');
    }
    final list = (res.data is Map ? res.data['data'] : res.data) as List? ?? const [];
    return list
        .map((e) => ReportSummary(e['key'] as String, (e['label'] ?? e['key']) as String))
        .toList();
  }

  Future<ReportData> run(String key) async {
    final res = await _api.dio.get<dynamic>('/reports/$key');
    if (res.statusCode != 200) {
      throw Exception('No se pudo correr el reporte (${res.statusCode}).');
    }
    final d = (res.data is Map ? res.data['data'] : res.data) as Map;
    final meta = (d['columns'] as Map?) ?? const {};

    final columns = <ReportColumn>[
      for (final dim in (meta['dimensions'] as List? ?? const []))
        ReportColumn(dim['key'] as String, (dim['label'] ?? dim['key']) as String),
      for (final m in (meta['measures'] as List? ?? const []))
        ReportColumn(m['key'] as String, (m['label'] ?? m['key']) as String),
    ];

    final rows = ((d['rows'] as List?) ?? const [])
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();

    return ReportData(columns: columns, rows: rows);
  }
}

final reportsRepositoryProvider = Provider<ReportsRepository>(
  (ref) => ReportsRepository(ref.watch(apiClientProvider)),
);

final reportsListProvider = FutureProvider.autoDispose<List<ReportSummary>>(
  (ref) => ref.watch(reportsRepositoryProvider).list(),
);

final reportDataProvider = FutureProvider.autoDispose.family<ReportData, String>(
  (ref, key) => ref.watch(reportsRepositoryProvider).run(key),
);
