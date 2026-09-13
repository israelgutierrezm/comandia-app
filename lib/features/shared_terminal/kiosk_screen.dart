import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'shared_terminal.dart';

/// La antesala del kiosco (ADR-014). Una sola pantalla con dos caras según el estado:
///  - **Sin emparejar**: se pega el secreto de enrolamiento para volver este aparato una terminal.
///  - **En el bloqueo**: cada operador teclea su código de empleado + PIN para entrar a operar.
///
/// La navegación la hace el router al cambiar [KioskStatus]: emparejar deja en el bloqueo; identificarse
/// lleva al POS; el 401 por inactividad o «salir» regresan aquí.
class KioskScreen extends ConsumerStatefulWidget {
  const KioskScreen({super.key});

  @override
  ConsumerState<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends ConsumerState<KioskScreen> {
  final _secret = TextEditingController();
  final _employeeCode = TextEditingController();
  final _pin = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _secret.dispose();
    _employeeCode.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
      // La navegación (a POS o al bloqueo) la hace el router al cambiar el estado.
    } on PairError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on IdentifyError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo conectar con el servidor.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(kioskControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: status == KioskStatus.unpaired
                ? _pairing(scheme)
                : _lock(scheme),
          ),
        ),
      ),
    );
  }

  // --- Sin emparejar: pegar el secreto ---
  Widget _pairing(ColorScheme scheme) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.point_of_sale_outlined, size: 56, color: scheme.primary),
          const SizedBox(height: 12),
          Text('Terminal compartida',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Pega el secreto que te dio la administración al enrolar esta terminal.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.outline)),
          const SizedBox(height: 24),
          TextField(
            controller: _secret,
            minLines: 2,
            maxLines: 3,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Secreto de enrolamiento'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _loading ? null : () => _run(() => ref.read(kioskControllerProvider.notifier).pair(_secret.text)),
            child: _loading
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Emparejar'),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _loading ? null : () => context.go('/login'),
            child: const Text('Volver al acceso de usuario'),
          ),
        ],
      );

  // --- En el bloqueo: código + PIN ---
  Widget _lock(ColorScheme scheme) {
    final labels = ref.watch(kioskLabelsProvider).valueOrNull;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.lock_outline, size: 56, color: scheme.primary),
        const SizedBox(height: 12),
        Text(labels?.terminalName ?? 'Terminal compartida',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        if (labels?.branchName != null) ...[
          const SizedBox(height: 4),
          Text(labels!.branchName!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.outline)),
        ],
        const SizedBox(height: 24),
        TextField(
          controller: _employeeCode,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Código de empleado'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _pin,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          decoration: const InputDecoration(labelText: 'PIN'),
          onSubmitted: (_) => _loading ? null : _identify(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!, style: TextStyle(color: scheme.error)),
        ],
        const SizedBox(height: 22),
        FilledButton(
          onPressed: _loading ? null : _identify,
          child: _loading
              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Text('Entrar'),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: _loading ? null : _confirmUnpair,
          child: Text('Desemparejar este aparato', style: TextStyle(color: scheme.outline)),
        ),
      ],
    );
  }

  void _identify() {
    _run(() => ref.read(kioskControllerProvider.notifier).identify(
          employeeCode: _employeeCode.text,
          pin: _pin.text,
        ));
    _pin.clear();
  }

  Future<void> _confirmUnpair() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Desemparejar?'),
        content: const Text('Este aparato dejará de ser una terminal compartida y volverá al acceso de usuario.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Desemparejar')),
        ],
      ),
    );
    if (ok == true) await ref.read(kioskControllerProvider.notifier).unpair();
  }
}
