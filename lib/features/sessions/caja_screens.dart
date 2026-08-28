import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pos/pos.dart' show PaymentMethod, paymentMethodsProvider;
import '../supervision/supervision.dart' show CutMethod;
import 'sessions.dart';

const _numeric = TextInputType.numberWithOptions(decimal: true);
final _onlyMoney = FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'));
String _fmt(String s) => (double.tryParse(s.trim()) ?? 0).toStringAsFixed(2);

// ---------------------------------------------------------------------------
// Abrir turno (gerente: necesita listar terminales)
// ---------------------------------------------------------------------------

class OpenSessionScreen extends ConsumerStatefulWidget {
  const OpenSessionScreen({super.key});

  @override
  ConsumerState<OpenSessionScreen> createState() => _OpenSessionScreenState();
}

class _OpenSessionScreenState extends ConsumerState<OpenSessionScreen> {
  Terminal? _terminal;
  final _float = TextEditingController(text: '0.00');
  bool _busy = false;

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _open() async {
    final t = _terminal;
    if (t == null) return _snack('Elige una terminal.');
    final f = double.tryParse(_float.text.trim());
    if (f == null || f < 0) return _snack('Captura un fondo válido.');

    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    try {
      await ref.read(sessionsRepositoryProvider).openSession(t.ulid, f.toStringAsFixed(2));
      ref.invalidate(sessionsListProvider('open'));
      _snack('Turno abierto.');
      navigator.pop();
    } on CajaError catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No se pudo abrir el turno.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final terminals = ref.watch(terminalsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Abrir turno')),
      body: terminals.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$e', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => ref.invalidate(terminalsProvider), child: const Text('Reintentar')),
            ]),
          ),
        ),
        data: (list) => list.isEmpty
            ? const Center(child: Text('No hay terminales activas en esta sucursal.'))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Terminal', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in list)
                        ChoiceChip(
                          label: Text(t.branchName == null ? t.name : '${t.name} · ${t.branchName}'),
                          selected: _terminal?.ulid == t.ulid,
                          onSelected: (_) => setState(() => _terminal = t),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _float,
                    keyboardType: _numeric,
                    inputFormatters: [_onlyMoney],
                    decoration: const InputDecoration(
                      labelText: 'Fondo inicial',
                      prefixText: '\$ ',
                      border: OutlineInputBorder(),
                      helperText: 'El cambio con el que abre la caja. Puede ser 0.',
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _open,
                    child: _busy
                        ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : const Text('Abrir turno'),
                  ),
                ],
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cerrar turno (cajero: declara y cierra; el corte puede ser ciego)
// ---------------------------------------------------------------------------

class CloseSessionScreen extends ConsumerStatefulWidget {
  const CloseSessionScreen({super.key, required this.session});

  final SessionSummary session;

  @override
  ConsumerState<CloseSessionScreen> createState() => _CloseSessionScreenState();
}

class _CloseSessionScreenState extends ConsumerState<CloseSessionScreen> {
  final Map<String, TextEditingController> _amounts = {};
  final _notes = TextEditingController();
  bool _busy = false;

  TextEditingController _ctrl(String ulid) => _amounts.putIfAbsent(ulid, () => TextEditingController(text: '0.00'));

  @override
  void dispose() {
    for (final c in _amounts.values) {
      c.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _close(List<PaymentMethod> methods) async {
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final repo = ref.read(sessionsRepositoryProvider);
    try {
      final declarations = [
        for (final m in methods)
          {'payment_method_ulid': m.ulid, 'declared_amount': _fmt(_ctrl(m.ulid).text)},
      ];
      await repo.declare(widget.session.ulid, 'close', declarations);
      await repo.closeSession(widget.session.ulid, notes: _notes.text.trim().isEmpty ? null : _notes.text.trim());

      ref.invalidate(sessionsListProvider('open'));
      ref.invalidate(sessionsListProvider('closed'));

      // El corte puede estar prohibido para este rol (arqueo ciego): no es un error.
      List<CutMethod>? cut;
      try {
        cut = await repo.cut(widget.session.ulid);
      } on CutForbidden {
        cut = null;
      } catch (_) {
        cut = null;
      }

      if (mounted) await _closedDialog(cut);
      navigator.pop();
    } on CajaError catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No se pudo cerrar el turno.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closedDialog(List<CutMethod>? cut) {
    return showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Turno cerrado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cut == null)
              const Text('El corte lo revisa un supervisor.')
            else
              for (final r in cut)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(r.method),
                      Text(
                        r.difference == null ? '—' : '\$${r.difference}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: (r.difference != null && r.difference!.startsWith('-')) ? Theme.of(context).colorScheme.error : null,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Listo'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final methods = ref.watch(paymentMethodsProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Cerrar turno ${widget.session.folio}')),
      body: methods.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$e', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => ref.invalidate(paymentMethodsProvider), child: const Text('Reintentar')),
            ]),
          ),
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Efectivo y pagos contados', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Declara lo que contaste por método. Cero también cuenta.',
                style: TextStyle(color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 12),
            for (final m in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _ctrl(m.ulid),
                  keyboardType: _numeric,
                  inputFormatters: [_onlyMoney],
                  decoration: InputDecoration(labelText: m.name, prefixText: '\$ ', border: const OutlineInputBorder(), isDense: true),
                ),
              ),
            TextField(
              controller: _notes,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'Notas (opcional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : () => _close(list),
              child: _busy
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('Declarar y cerrar'),
            ),
          ],
        ),
      ),
    );
  }
}
