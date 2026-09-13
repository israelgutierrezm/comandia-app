import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';
import 'shared_terminal_storage.dart';
import 'token_storage.dart';

/// Providers de la infraestructura compartida: almacenamiento seguro, guardado
/// del token y el cliente HTTP. Todo lo demás (repositorios, controladores)
/// cuelga de éstos.
final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => TokenStorage(ref.watch(secureStorageProvider)),
);

/// Credencial de la terminal compartida (ADR-014). Aparte de la del usuario.
final sharedTerminalStorageProvider = Provider<SharedTerminalStorage>(
  (ref) => SharedTerminalStorage(ref.watch(secureStorageProvider)),
);

/// Señal de «una petición del kiosco vino 401». La emite [ApiClient] y la escucha el controlador del
/// kiosco para volver al bloqueo. Vive en el núcleo (no en la feature) para no invertir la dependencia:
/// el cliente HTTP no conoce la feature; la feature escucha esta señal.
final kioskUnauthorizedTickProvider = StateProvider<int>((ref) => 0);

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    ref.watch(tokenStorageProvider),
    ref.watch(sharedTerminalStorageProvider),
    () => ref.read(kioskUnauthorizedTickProvider.notifier).state++,
  ),
);
