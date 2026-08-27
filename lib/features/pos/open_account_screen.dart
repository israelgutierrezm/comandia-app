import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_screen.dart';
import 'pos.dart';

/// Abrir una cuenta nueva: para llevar (un toque) o en una mesa del salón. Las mesas vienen ya filtradas a las libres;
/// tocar una la abre y entra a la cuenta.
class OpenAccountScreen extends ConsumerStatefulWidget {
  const OpenAccountScreen({super.key});

  @override
  ConsumerState<OpenAccountScreen> createState() => _OpenAccountScreenState();
}

class _OpenAccountScreenState extends ConsumerState<OpenAccountScreen> {
  bool _busy = false;

  Future<void> _open(Future<AccountSummary> Function() opener) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final account = await opener();
      ref.invalidate(openAccountsProvider);
      ref.invalidate(availableTablesProvider);
      // Reemplaza esta pantalla por la cuenta: al volver, se cae en la lista, no en el selector.
      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => AccountScreen(ulid: account.ulid, title: account.displayName)),
      );
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('No se pudo abrir la cuenta.')));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tables = ref.watch(availableTablesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Abrir cuenta')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _open(() => ref.read(posRepositoryProvider).openTakeout()),
                icon: const Icon(Icons.takeout_dining),
                label: const Text('Para llevar'),
              ),
              const SizedBox(height: 20),
              Text('Mesas disponibles', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              tables.when(
                loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                error: (e, _) => Column(children: [
                  Text('$e', textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: () => ref.invalidate(availableTablesProvider), child: const Text('Reintentar')),
                ]),
                data: (list) => list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text('No hay mesas libres.', style: TextStyle(color: theme.colorScheme.outline)),
                      )
                    : _tablesByZone(context, list),
              ),
            ],
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tablesByZone(BuildContext context, List<RestaurantTable> tables) {
    final byZone = <String, List<RestaurantTable>>{};
    for (final t in tables) {
      (byZone[t.zoneName ?? 'Sin zona'] ??= []).add(t);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in byZone.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text(entry.key, style: TextStyle(color: Theme.of(context).colorScheme.outline, fontWeight: FontWeight.w600)),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final t in entry.value) _tableCard(t)],
          ),
        ],
      ],
    );
  }

  Widget _tableCard(RestaurantTable t) {
    return SizedBox(
      width: 104,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: _busy ? null : () => _open(() => ref.read(posRepositoryProvider).openTable(t.ulid)),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Column(
              children: [
                Text(t.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                if (t.seats != null) ...[
                  const SizedBox(height: 4),
                  Text('${t.seats} lugares', style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
