import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cobro_screen.dart';
import 'pos.dart';

String _money(String? v) => v == null ? '—' : '\$$v';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key, required this.ulid, required this.title});

  final String ulid;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(accountProvider(ulid));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          bottom: const TabBar(tabs: [Tab(text: 'Marcar'), Tab(text: 'Cuenta')]),
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$e', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: () => ref.invalidate(accountProvider(ulid)), child: const Text('Reintentar')),
              ]),
            ),
          ),
          data: (account) => TabBarView(
            children: [_MarcarTab(account: account), _CuentaTab(account: account)],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Marcar: catálogo de 1 toque + carrito local
// ---------------------------------------------------------------------------

class _MarcarTab extends ConsumerStatefulWidget {
  const _MarcarTab({required this.account});
  final Account account;

  @override
  ConsumerState<_MarcarTab> createState() => _MarcarTabState();
}

class _MarcarTabState extends ConsumerState<_MarcarTab> {
  String _search = '';
  String? _topCategory; // categoría de nivel 1 (pestaña); null = todas
  String? _subCategory; // subcategoría de nivel 2 (chip); null = todas dentro del top
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const <PosCategory>[];
    final cart = ref.watch(captureCartProvider(widget.account.ulid));

    return catalog.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$e', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => ref.invalidate(catalogProvider), child: const Text('Reintentar')),
          ]),
        ),
      ),
      data: (articles) {
        // Cada artículo cuelga de una categoría (nivel 1 o 2). Este mapa lleva de cualquier categoría a su nivel 1,
        // para poder filtrar por pestaña aunque el artículo esté en una subcategoría.
        final topOf = <String, String>{};
        for (final top in cats) {
          topOf[top.ulid] = top.ulid;
          for (final sub in top.children) {
            topOf[sub.ulid] = top.ulid;
          }
        }

        final q = _search.trim().toLowerCase();
        final filtered = articles.where((a) {
          final top = a.categoryUlid == null ? null : topOf[a.categoryUlid];
          final inTop = _topCategory == null || top == _topCategory;
          final inSub = _subCategory == null || a.categoryUlid == _subCategory;
          final match = q.isEmpty || a.name.toLowerCase().contains(q);
          return inTop && inSub && match;
        }).toList();

        final subs = _subsOf(_topCategory, cats);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar artículo…', isDense: true),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            if (cats.isNotEmpty)
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _topChip(null, 'Todas'),
                    for (final c in cats) _topChip(c.ulid, c.name),
                  ],
                ),
              ),
            if (subs.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _subChip(null, 'Todos'),
                    for (final s in subs) _subChip(s.ulid, s.name),
                  ],
                ),
              ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('Sin resultados.'))
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 180,
                        mainAxisExtent: 196,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => _ProductCard(
                        article: filtered[i],
                        onAdd: () => ref.read(captureCartProvider(widget.account.ulid).notifier).add(filtered[i]),
                      ),
                    ),
            ),
            if (cart.isNotEmpty) _CartPanel(account: widget.account, cart: cart, sending: _sending, onCapture: _capture),
          ],
        );
      },
    );
  }

  /// Las subcategorías (nivel 2) de la categoría de nivel 1 seleccionada; vacío si no hay top o no tiene hijas.
  List<PosCategory> _subsOf(String? topUlid, List<PosCategory> cats) {
    if (topUlid == null) return const [];
    for (final c in cats) {
      if (c.ulid == topUlid) return c.children;
    }
    return const [];
  }

  Widget _topChip(String? value, String label) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _topCategory == value,
          // Cambiar de pestaña reinicia la subcategoría: los chips de abajo son de OTRA categoría.
          onSelected: (_) => setState(() {
            _topCategory = value;
            _subCategory = null;
          }),
        ),
      );

  Widget _subChip(String? value, String label) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _subCategory == value,
          onSelected: (_) => setState(() => _subCategory = value),
        ),
      );

  Future<void> _capture() async {
    final ulid = widget.account.ulid;
    final cart = ref.read(captureCartProvider(ulid));
    if (cart.isEmpty || _sending) return;

    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref.read(posRepositoryProvider).capture(ulid, widget.account.version, cart);
      ref.read(captureCartProvider(ulid).notifier).clear();
      ref.invalidate(accountProvider(ulid));
      messenger.showSnackBar(const SnackBar(content: Text('Capturado.')));
    } on StaleAccount {
      ref.invalidate(accountProvider(ulid));
      messenger.showSnackBar(const SnackBar(content: Text('La cuenta cambió en otra terminal; se recargó.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('No se pudo capturar.')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.article, required this.onAdd});
  final CatalogArticle article;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Tocar la tarjeta O el «+» marca el artículo: en una pantalla táctil, cualquiera de los dos es lo natural.
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onAdd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _Photo(url: article.imageUrl)),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(article.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(_money(article.basePrice), style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                      ],
                    ),
                  ),
                  Material(
                    color: theme.colorScheme.primary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onAdd,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.add, size: 20, color: theme.colorScheme.onPrimary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La foto de un artículo: cubre el espacio; con caída elegante a un ícono cuando no hay foto o la descarga falla.
class _Photo extends StatelessWidget {
  const _Photo({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(Icons.restaurant_menu, color: theme.colorScheme.outline, size: 28),
    );

    if (url == null) return placeholder;

    return Image.network(
      url!,
      fit: BoxFit.cover,
      width: double.infinity,
      errorBuilder: (_, _, _) => placeholder,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : ColoredBox(
              color: theme.colorScheme.surfaceContainerHighest,
              child: const Center(child: SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
    );
  }
}

class _CartPanel extends ConsumerWidget {
  const _CartPanel({required this.account, required this.cart, required this.sending, required this.onCapture});
  final Account account;
  final List<CaptureLine> cart;
  final bool sending;
  final Future<void> Function() onCapture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(captureCartProvider(account.ulid).notifier);
    final count = cart.fold<int>(0, (s, l) => s + l.quantity);

    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 168),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final l in cart)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(child: Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                          IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.remove_circle_outline), onPressed: () => notifier.dec(l.articleUlid)),
                          Text('${l.quantity}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.add_circle_outline), onPressed: () => notifier.inc(l.articleUlid)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            FilledButton(
              onPressed: sending ? null : onCapture,
              child: sending
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text('Capturar $count ${count == 1 ? 'artículo' : 'artículos'}'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cuenta: consumo, totales y comandar
// ---------------------------------------------------------------------------

class _CuentaTab extends ConsumerWidget {
  const _CuentaTab({required this.account});
  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = account.orders
        .where((o) => account.items.any((i) => i.orderUlid == o.ulid && i.captured))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Consumo', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (account.items.isEmpty)
                  const Text('Todavía no se ha capturado nada.')
                else
                  for (final i in account.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Text('${i.quantity}× ', style: const TextStyle(fontWeight: FontWeight.w600)),
                          Expanded(
                            child: Text(
                              i.articleName,
                              style: TextStyle(decoration: i.cancelled ? TextDecoration.lineThrough : null),
                            ),
                          ),
                          Text(_money(i.lineTotal)),
                          const SizedBox(width: 8),
                          Text(i.statusLabel ?? '', style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12)),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _total(context, 'Subtotal', account.totals['subtotal']),
                _total(context, 'Descuentos', account.totals['discount_total']),
                _total(context, 'IVA incluido', account.totals['vat_total']),
                _total(context, 'Total', account.totals['total'], strong: true),
                _total(context, 'Falta', account.totals['due']),
              ],
            ),
          ),
        ),
        // «Cobrar» solo si el rol activo puede (pos.accounts.charge) y queda saldo. El servidor sigue decidiendo.
        if ((ref.watch(permissionsProvider).valueOrNull?.contains('pos.accounts.charge') ?? false) &&
            (double.tryParse(account.totals['due'] ?? '0') ?? 0) > 0) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => CobroScreen(account: account)),
            ),
            icon: const Icon(Icons.payments),
            label: Text('Cobrar ${_money(account.totals['due'])}'),
          ),
        ],
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Comandar', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Manda a preparar lo capturado.', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 8),
          for (final o in pending)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FilledButton.tonal(
                onPressed: () => _command(context, ref, o),
                child: Text('Comandar orden ${o.sequence}'),
              ),
            ),
        ],
      ],
    );
  }

  Widget _total(BuildContext context, String label, String? value, {bool strong = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
            Text(_money(value), style: TextStyle(fontWeight: strong ? FontWeight.w700 : FontWeight.w500, fontSize: strong ? 16 : 14)),
          ],
        ),
      );

  Future<void> _command(BuildContext context, WidgetRef ref, AccountOrder order) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(posRepositoryProvider).command(account.ulid, order.ulid, account.version);
      ref.invalidate(accountProvider(account.ulid));
      messenger.showSnackBar(const SnackBar(content: Text('Comandado.')));
    } on StaleAccount {
      ref.invalidate(accountProvider(account.ulid));
      messenger.showSnackBar(const SnackBar(content: Text('La cuenta cambió en otra terminal; se recargó.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('No se pudo comandar.')));
    }
  }
}
