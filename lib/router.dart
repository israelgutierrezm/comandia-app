import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/auth.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_shell.dart';
import 'features/shared_terminal/kiosk_screen.dart';
import 'features/shared_terminal/shared_terminal.dart';

/// Puente Riverpod → Listenable para que go_router reevalúe la redirección cuando cambia el estado de
/// sesión de usuario o el del kiosco (ADR-014).
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(authControllerProvider, (_, _) => notifyListeners());
    ref.listen(kioskControllerProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final kiosk = ref.read(kioskControllerProvider);
      final loc = state.matchedLocation;

      // Ambos controladores restauran de forma asíncrona al arrancar: mientras alguno no sepa, al splash.
      if (auth == AuthStatus.unknown || kiosk == KioskStatus.unknown) {
        return loc == '/' ? null : '/';
      }

      // El modo kiosco (dispositivo emparejado) manda sobre el acceso de usuario.
      switch (kiosk) {
        case KioskStatus.locked:
          return loc == '/kiosk' ? null : '/kiosk';
        case KioskStatus.operating:
          // Opera el POS (con el token del dispositivo): fuera del bloqueo, del acceso y del splash.
          return (loc == '/kiosk' || loc == '/login' || loc == '/') ? '/home' : null;
        case KioskStatus.unpaired:
          // Flujo normal de usuario, pero `/kiosk` sigue alcanzable para emparejar este aparato.
          if (loc == '/kiosk') return null;
          if (auth == AuthStatus.unauthenticated) return loc == '/login' ? null : '/login';
          if (loc == '/login' || loc == '/') return '/home';
          return null;
        case KioskStatus.unknown:
          return loc == '/' ? null : '/';
      }
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const _Splash()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/kiosk', builder: (_, _) => const KioskScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeShell()),
    ],
  );
});

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
