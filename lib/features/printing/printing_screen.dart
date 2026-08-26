import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'print_bridge.dart';

/// Pestaña «Impresión»: convierte este dispositivo en un agente de impresión.
///
/// El puente autentica con un token que emite el administrador del negocio; mientras está activo sondea trabajos y los
/// manda a las impresoras de red (TCP). Pensado para dejarse encendido en una caja o tablet fija.
class PrintingTab extends ConsumerStatefulWidget {
  const PrintingTab({super.key});

  @override
  ConsumerState<PrintingTab> createState() => _PrintingTabState();
}

class _PrintingTabState extends ConsumerState<PrintingTab> {
  final _tokenCtrl = TextEditingController();

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(printBridgeProvider);
    final bridge = ref.read(printBridgeProvider.notifier);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!state.hasToken) _tokenSetup(context, bridge) else _control(context, state, bridge),
        if (state.lastError != null) ...[
          const SizedBox(height: 12),
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: theme.colorScheme.onErrorContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(state.lastError!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (state.hasToken) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Text('Últimos trabajos', style: theme.textTheme.titleMedium),
              const Spacer(),
              if (state.busy)
                const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 8),
          if (state.log.isEmpty)
            Text(
              state.active ? 'Escuchando… los trabajos aparecerán aquí.' : 'Activa el puente para empezar a imprimir.',
              style: TextStyle(color: theme.colorScheme.outline),
            )
          else
            for (final e in state.log) _logTile(context, e),
        ],
      ],
    );
  }

  Widget _tokenSetup(BuildContext context, PrintBridge bridge) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Conectar la impresión', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Pega el token del agente de impresión. Lo genera el administrador del negocio y queda ligado a una '
              'sucursal; este dispositivo imprimirá lo de esa sucursal.',
              style: TextStyle(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _tokenCtrl,
              decoration: const InputDecoration(
                labelText: 'Token del agente',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () async {
                  final value = _tokenCtrl.text.trim();
                  if (value.isEmpty) return;
                  await bridge.saveToken(value);
                  _tokenCtrl.clear();
                },
                icon: const Icon(Icons.link),
                label: const Text('Guardar token'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _control(BuildContext context, BridgeState state, PrintBridge bridge) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Puente activo', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                state.active ? 'Escuchando trabajos de impresión.' : 'Detenido.',
                style: TextStyle(color: theme.colorScheme.outline),
              ),
              value: state.active,
              onChanged: (on) => on ? bridge.start() : bridge.stop(),
            ),
            const Divider(height: 1),
            Row(
              children: [
                TextButton.icon(
                  onPressed: state.busy ? null : () => bridge.poll(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Probar ahora'),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _confirmForget(context, bridge),
                  icon: const Icon(Icons.link_off),
                  label: const Text('Olvidar token'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmForget(BuildContext context, PrintBridge bridge) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Olvidar el token'),
        content: const Text('Este dispositivo dejará de imprimir hasta que captures un token de nuevo. ¿Continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Olvidar')),
        ],
      ),
    );
    if (ok == true) await bridge.forget();
  }

  Widget _logTile(BuildContext context, JobLog e) {
    final theme = Theme.of(context);
    final color = e.ok ? Colors.green : theme.colorScheme.error;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(e.ok ? Icons.check_circle : Icons.error, color: color),
      title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(e.detail),
      trailing: Text(_hms(e.at), style: TextStyle(color: theme.colorScheme.outline, fontSize: 12)),
    );
  }

  String _hms(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
