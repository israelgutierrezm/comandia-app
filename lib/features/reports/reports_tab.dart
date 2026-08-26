import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'reports.dart';

class ReportsTab extends ConsumerWidget {
  const ReportsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reportsListProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Retry(message: '$e', onRetry: () => ref.invalidate(reportsListProvider)),
      data: (reports) => reports.isEmpty
          ? const Center(child: Text('No hay reportes disponibles para tu rol.'))
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(reportsListProvider),
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: reports.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final r = reports[i];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.bar_chart),
                      title: Text(r.label),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => ReportDataScreen(reportKey: r.key, label: r.label)),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class ReportDataScreen extends ConsumerWidget {
  const ReportDataScreen({super.key, required this.reportKey, required this.label});
  final String reportKey;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reportDataProvider(reportKey));

    return Scaffold(
      appBar: AppBar(title: Text(label)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Retry(message: '$e', onRetry: () => ref.invalidate(reportDataProvider(reportKey))),
        data: (data) {
          if (data.rows.isEmpty) {
            return const Center(child: Text('El reporte no devolvió filas.'));
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                columns: [for (final c in data.columns) DataColumn(label: Text(c.label))],
                rows: [
                  for (final row in data.rows)
                    DataRow(
                      cells: [
                        for (final c in data.columns) DataCell(Text('${row[c.key] ?? '—'}')),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ]),
        ),
      );
}
