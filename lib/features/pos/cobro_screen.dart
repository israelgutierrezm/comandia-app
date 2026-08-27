import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pos.dart';

double? _parse(String? s) => s == null ? null : double.tryParse(s.trim());
String _fmt(double v) => v.toStringAsFixed(2);
String _money(String? s) => s == null ? '—' : '\$$s';

/// Cobra una cuenta: uno o varios pagos. Cuando lo pagado cubre el total, el servidor la pasa a `paid` y emite el ticket
/// final (que imprime por el puente). El servidor es la autoridad del cambio y de los totales; aquí solo se previsualiza.
class CobroScreen extends ConsumerStatefulWidget {
  const CobroScreen({super.key, required this.account});

  final Account account;

  @override
  ConsumerState<CobroScreen> createState() => _CobroScreenState();
}

class _CobroScreenState extends ConsumerState<CobroScreen> {
  final List<PaymentLine> _lines = [];

  PaymentMethod? _method;
  final _amount = TextEditingController();
  final _tendered = TextEditingController();
  final _reference = TextEditingController();
  final _tip = TextEditingController();

  bool _sending = false;

  @override
  void dispose() {
    _amount.dispose();
    _tendered.dispose();
    _reference.dispose();
    _tip.dispose();
    super.dispose();
  }

  double get _due => _parse(widget.account.totals['due'] ?? widget.account.totals['total']) ?? 0;
  double get _staged => _lines.fold(0, (s, l) => s + (_parse(l.amount) ?? 0));
  double get _remaining {
    final r = _due - _staged;
    return r < 0 ? 0 : r;
  }

  double? get _change {
    final t = _parse(_tendered.text);
    final a = _parse(_amount.text);
    if (_method?.allowsChange != true || t == null || a == null) return null;
    final c = t - a;
    return c < 0 ? 0 : c;
  }

  void _pickMethod(PaymentMethod m) {
    setState(() {
      _method = m;
      if (_amount.text.trim().isEmpty && _remaining > 0) _amount.text = _fmt(_remaining);
    });
  }

  /// La línea del formulario, si está completa. Null si falta método, monto válido o la referencia obligatoria.
  PaymentLine? _formLine() {
    final m = _method;
    final a = _parse(_amount.text);
    if (m == null || a == null || a <= 0) return null;
    if (m.requiresReference && _reference.text.trim().isEmpty) return null;
    return PaymentLine(
      method: m,
      amount: _fmt(a),
      tendered: _parse(_tendered.text) == null ? null : _fmt(_parse(_tendered.text)!),
      tip: _parse(_tip.text) == null ? null : _fmt(_parse(_tip.text)!),
      reference: _reference.text.trim().isEmpty ? null : _reference.text.trim(),
    );
  }

  void _resetForm() {
    _method = null;
    _amount.clear();
    _tendered.clear();
    _reference.clear();
    _tip.clear();
  }

  void _addAnother() {
    final line = _formLine();
    if (line == null) {
      _needForm();
      return;
    }
    setState(() {
      _lines.add(line);
      _resetForm();
    });
  }

  void _needForm() {
    final m = _method;
    final msg = m == null
        ? 'Elige un método y captura el monto.'
        : (m.requiresReference && _reference.text.trim().isEmpty)
            ? 'Este método necesita una referencia.'
            : 'Captura un monto válido.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _charge() async {
    final payments = [..._lines, if (_formLine() != null) _formLine()!];
    if (payments.isEmpty) {
      _needForm();
      return;
    }

    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final updated = await ref.read(posRepositoryProvider).charge(widget.account.ulid, widget.account.version, payments);
      ref.invalidate(accountProvider(widget.account.ulid));
      ref.invalidate(openAccountsProvider);

      final due = _parse(updated.totals['due']) ?? 0;
      if (due <= 0) {
        if (mounted) await _paidDialog(updated);
        navigator.pop();
      } else {
        messenger.showSnackBar(SnackBar(content: Text('Pago registrado. Falta ${_money(updated.totals['due'])}.')));
        navigator.pop();
      }
    } on StaleAccount {
      ref.invalidate(accountProvider(widget.account.ulid));
      messenger.showSnackBar(const SnackBar(content: Text('La cuenta cambió en otra terminal; ábrela de nuevo para cobrar.')));
      if (mounted) Navigator.of(context).pop();
    } on ChargeError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('No se pudo cobrar.')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _paidDialog(Account paid) {
    final change = _parse(paid.totals['change_total']) ?? 0;
    return showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cuenta cobrada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (change > 0)
              Text('Cambio a devolver: ${_money(paid.totals['change_total'])}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))
            else
              const Text('Pago exacto.'),
            const SizedBox(height: 8),
            const Text('El ticket se está imprimiendo.'),
          ],
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Listo'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final methods = ref.watch(paymentMethodsProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Cobrar · ${widget.account.displayName}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _totalRow(context, 'Total', widget.account.totals['total']),
                  const SizedBox(height: 4),
                  _totalRow(context, 'Falta', _fmt(_remaining), strong: true),
                ],
              ),
            ),
          ),
          if (_lines.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Pagos', style: theme.textTheme.titleMedium),
            for (var i = 0; i < _lines.length; i++)
              Card(
                child: ListTile(
                  dense: true,
                  title: Text(_lines[i].method.name),
                  subtitle: _lines[i].reference == null ? null : Text('Ref: ${_lines[i].reference}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_money(_lines[i].amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                      IconButton(
                        icon: const Icon(Icons.close),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _lines.removeAt(i)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          Text(_lines.isEmpty ? 'Pago' : 'Otro pago', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          methods.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Column(children: [
              Text('$e', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              FilledButton(onPressed: () => ref.invalidate(paymentMethodsProvider), child: const Text('Reintentar')),
            ]),
            data: (list) => _form(context, list),
          ),
        ],
      ),
    );
  }

  Widget _form(BuildContext context, List<PaymentMethod> list) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in list)
              ChoiceChip(
                label: Text(m.name),
                selected: _method?.ulid == m.ulid,
                onSelected: (_) => _pickMethod(m),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: const InputDecoration(labelText: 'Monto', prefixText: '\$ ', border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        if (_method?.allowsChange == true) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _tendered,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(labelText: 'Recibido', prefixText: '\$ ', border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          if (_change != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Cambio: ${_fmt(_change!)}',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
            ),
        ],
        if (_method?.requiresReference == true) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _reference,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Referencia', border: OutlineInputBorder()),
          ),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: _tip,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: const InputDecoration(labelText: 'Propina (opcional)', prefixText: '\$ ', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _sending ? null : _addAnother,
          icon: const Icon(Icons.add),
          label: const Text('Agregar y capturar otro pago'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _sending ? null : _charge,
          child: _sending
              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Text('Cobrar'),
        ),
      ],
    );
  }

  Widget _totalRow(BuildContext context, String label, String? value, {bool strong = false}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: strong ? 16 : 14)),
          Text(_money(value),
              style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w500, fontSize: strong ? 22 : 15)),
        ],
      );
}
