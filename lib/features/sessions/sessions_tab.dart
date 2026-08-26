import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../supervision/supervision.dart' show CutMethod;
import 'sessions.dart';

class SessionsTab extends ConsumerWidget {
  const SessionsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(sessionsFilterProvider);
    final async = ref.watch(sessionsListProvider(status));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              _chip(ref, status, 'open', 'Abiertos'),
              const SizedBox(width: 8),
              _chip(ref, status, 'closed', 'Cerrados'),
            ],
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _Retry(message: '$e', onRetry: () => ref.invalidate(sessionsListProvider(status))),
            data: (sessions) => sessions.isEmpty
                ? const Center(child: Text('No hay turnos en este estado.'))
                : RefreshIndicator(
                    onRefresh: () async => ref.invalidate(sessionsListProvider(status)),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: sessions.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _SessionTile(session: sessions[i]),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _chip(WidgetRef ref, String current, String value, String label) => ChoiceChip(
        label: Text(label),
        selected: current == value,
        onSelected: (_) => ref.read(sessionsFilterProvider.notifier).state = value,
      );
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});
  final SessionSummary session;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text('Turno ${session.folio}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([
          if (session.terminalName != null) session.terminalName,
          if (session.openedAt != null) 'Abierta ${session.openedAt}',
        ].whereType<String>().join(' · ')),
        trailing: Chip(label: Text(session.statusLabel), visualDensity: VisualDensity.compact),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SessionDetailScreen(session: session)),
        ),
      ),
    );
  }
}

class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key, required this.session});
  final SessionSummary session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cut = ref.watch(sessionCutProvider(session.ulid));

    return Scaffold(
      appBar: AppBar(title: Text('Turno ${session.folio}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(session.statusLabel, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (session.terminalName != null) Text(session.terminalName!),
                  if (session.openedAt != null) Text('Abierta ${session.openedAt}'),
                  if (session.closedAt != null) Text('Cerrada ${session.closedAt}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Corte', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  cut.when(
                    loading: () => const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())),
                    error: (e, _) => Text(
                      e is CutForbidden
                          ? 'No tienes permiso para ver el corte (precorte ciego).'
                          : 'No se pudo cargar el corte.',
                    ),
                    data: (rows) => rows.isEmpty ? const Text('Sin corte que mostrar.') : _CutTable(rows: rows),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CutTable extends StatelessWidget {
  const _CutTable({required this.rows});
  final List<CutMethod> rows;

  @override
  Widget build(BuildContext context) {
    String money(String? v) => v == null ? '—' : '\$$v';
    return Column(
      children: [
        const Row(children: [
          Expanded(flex: 2, child: Text('Método', style: TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text('Esperado', textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text('Declarado', textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text('Dif.', textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 6),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(flex: 2, child: Text(r.method)),
              Expanded(child: Text(money(r.expected), textAlign: TextAlign.end)),
              Expanded(child: Text(money(r.declared), textAlign: TextAlign.end)),
              Expanded(
                child: Text(
                  money(r.difference),
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: (r.difference != null && r.difference!.startsWith('-')) ? Theme.of(context).colorScheme.error : null,
                  ),
                ),
              ),
            ]),
          ),
      ],
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
