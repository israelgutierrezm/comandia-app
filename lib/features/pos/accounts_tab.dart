import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_screen.dart';
import 'open_account_screen.dart';
import 'pos.dart';

class AccountsTab extends ConsumerWidget {
  const AccountsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(openAccountsProvider);

    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$e', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => ref.invalidate(openAccountsProvider), child: const Text('Reintentar')),
            ]),
          ),
        ),
        data: (accounts) => accounts.isEmpty
            ? const Center(child: Text('No hay cuentas abiertas.\nAbre una en mesa o para llevar.', textAlign: TextAlign.center))
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(openAccountsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: accounts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final a = accounts[i];
                    return Card(
                      child: ListTile(
                        title: Text(a.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${a.folio} · ${a.statusLabel}'),
                        trailing: a.due == null ? null : Text('Falta \$${a.due}', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => AccountScreen(ulid: a.ulid, title: a.displayName)),
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const OpenAccountScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Abrir cuenta'),
      ),
    );
  }
}
