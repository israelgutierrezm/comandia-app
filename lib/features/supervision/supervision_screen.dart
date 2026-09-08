import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'supervision.dart';

/// Pestaña «Resumen»: contexto de la sesión (rol y sucursal activos) y la caja
/// abierta del turno con su corte. Vive dentro del shell con pestañas, así que
/// no trae Scaffold ni barra propia.
class ResumenTab extends ConsumerWidget {
  const ResumenTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(supervisionControllerProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorState(
        message: '$e',
        onRetry: () => ref.read(supervisionControllerProvider.notifier).refresh(),
      ),
      data: (data) => RefreshIndicator(
        onRefresh: () => ref.read(supervisionControllerProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ContextCard(context: data.context),
            const SizedBox(height: 16),
            _SessionCard(data: data),
          ],
        ),
      ),
    );
  }
}

class _ContextCard extends StatelessWidget {
  const _ContextCard({required this.context});
  final AppContext context;

  @override
  Widget build(BuildContext ctx) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tenantName, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 10),
            _row(ctx, 'Persona', context.membershipName ?? '—'),
            _row(ctx, 'Rol activo', context.roleName ?? '—'),
            _row(ctx, 'Sucursal', context.branchName ?? '—'),
            _row(ctx, 'Permisos', '${context.permissionsCount}'),
            if (context.isReadOnly)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Cuenta en sólo lectura',
                    style: TextStyle(color: Theme.of(ctx).colorScheme.tertiary)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext ctx, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: Theme.of(ctx).colorScheme.outline)),
            Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.data});
  final SupervisionData data;

  @override
  Widget build(BuildContext context) {
    final session = data.session;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Caja del turno', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            if (session == null)
              const Text('No hay caja abierta en esta sucursal.')
            else ...[
              Text('Turno ${session.folio}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              if (session.terminalName != null) Text(session.terminalName!),
              if (session.openedAt != null)
                Text('Abierta ${session.openedAt}',
                    style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12)),
              const Divider(height: 24),
              if (data.cutForbidden)
                const Text('No tienes permiso para ver el corte (precorte ciego).')
              else if (data.cut.isEmpty)
                const Text('Sin corte que mostrar todavía.')
              else ...[
                if (data.summary != null) ...[
                  _ResumenTurno(summary: data.summary!),
                  const Divider(height: 24),
                ],
                _CutTable(rows: data.cut),
              ],
            ],
          ],
        ),
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

/// El resumen del turno: ventas, cómo se pagó por método, gastos, retiros y el
/// efectivo teórico (resaltado). Espeja lo que muestra la caja del admin web.
class _ResumenTurno extends StatelessWidget {
  const _ResumenTurno({required this.summary});
  final CutSummary summary;

  @override
  Widget build(BuildContext context) {
    String money(String? v) => v == null ? '—' : '\$$v';
    final outline = Theme.of(context).colorScheme.outline;

    Widget row(String label, String value, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(color: outline)),
              Text(
                value,
                style: TextStyle(
                  fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
                  color: strong ? Theme.of(context).colorScheme.primary : null,
                ),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Resumen del turno', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        row('Ventas del turno', money(summary.salesTotal)),
        for (final p in summary.paymentsByMethod) row(p.method, money(p.amount)),
        row('Gastos', money(summary.expensesTotal)),
        row('Retiros', money(summary.withdrawalsTotal)),
        row('Efectivo teórico', money(summary.expectedCash), strong: true),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 44, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
