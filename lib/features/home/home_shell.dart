import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth.dart';
import '../pos/accounts_tab.dart';
import '../printing/printing_screen.dart';
import '../reports/reports_tab.dart';
import '../sessions/sessions_tab.dart';
import '../shared_terminal/shared_terminal.dart';
import '../supervision/supervision_screen.dart';

/// El hogar de la app: las funciones por pestañas. La sesión (cerrar) vive en la
/// barra superior, común a todas.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  /// Mientras se cierra la sesión: el servidor tiene unos segundos para revocar el token (más sin red). La pantalla lo
  /// dice, «Salir» queda deshabilitado y las pestañas se desmontan para que nada siga operando a medio cierre.
  bool _signingOut = false;

  static const _titles = ['Resumen', 'Cuentas', 'Turnos', 'Reportes', 'Impresión'];
  static const _tabs = [ResumenTab(), AccountsTab(), SessionsTab(), ReportsTab(), PrintingTab()];

  Future<void> _signOut() async {
    // Un segundo toque antes de que se redibuje el botón no lanza otro cierre.
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await ref.read(authControllerProvider.notifier).logout();
    } finally {
      // Normalmente el router ya se llevó esta pantalla; si seguimos aquí, el botón vuelve a servir.
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // En modo kiosco (ADR-014) «Salir» BLOQUEA: olvida al operador y vuelve al PIN, sin cerrar el
    // emparejamiento del dispositivo. En modo usuario cierra la sesión de usuario.
    final kioskOperating = ref.watch(kioskControllerProvider) == KioskStatus.operating;

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          IconButton(
            tooltip: kioskOperating ? 'Bloquear' : 'Salir',
            icon: Icon(kioskOperating ? Icons.lock_outline : Icons.logout),
            onPressed: kioskOperating
                ? () => ref.read(kioskControllerProvider.notifier).lock()
                : (_signingOut ? null : _signOut),
          ),
        ],
      ),
      body: _signingOut ? const _SigningOut() : IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: _signingOut ? null : NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Resumen',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Cuentas',
          ),
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale),
            label: 'Turnos',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Reportes',
          ),
          NavigationDestination(
            icon: Icon(Icons.print_outlined),
            selectedIcon: Icon(Icons.print),
            label: 'Impresión',
          ),
        ],
      ),
    );
  }
}

/// Lo que se ve mientras se cierra la sesión.
class _SigningOut extends StatelessWidget {
  const _SigningOut();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Cerrando sesión…'),
          ],
        ),
      );
}
