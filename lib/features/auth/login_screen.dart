import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit({String? tenantUlid}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ref.read(authControllerProvider.notifier).login(
            email: _email.text.trim(),
            password: _password.text,
            tenantUlid: tenantUlid,
          );
      // La navegación la hace el router al cambiar el estado de sesión.
    } on NeedTenantSelection catch (selection) {
      if (mounted) await _pickTenant(selection.options);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo conectar con el servidor.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickTenant(List<TenantOption> options) async {
    final chosen = await showDialog<TenantOption>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Elige un negocio'),
        children: options
            .map((o) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, o),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(o.name),
                  ),
                ))
            .toList(),
      ),
    );

    if (chosen != null) await _submit(tenantUlid: chosen.ulid);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.storefront, size: 56, color: scheme.primary),
                const SizedBox(height: 12),
                Text('Comandia',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Supervisión',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.outline)),
                const SizedBox(height: 28),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Correo'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  onSubmitted: (_) => _loading ? null : _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: _loading ? null : () => _submit(),
                  child: _loading
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Text('Entrar'),
                ),
                const SizedBox(height: 6),
                // Alta de este aparato como terminal compartida (ADR-014): se pega el secreto de enrolamiento.
                TextButton.icon(
                  onPressed: _loading ? null : () => context.go('/kiosk'),
                  icon: const Icon(Icons.point_of_sale_outlined, size: 18),
                  label: const Text('Configurar como terminal compartida'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
