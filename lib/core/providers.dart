import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';
import 'device_name.dart';
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

/// Señal de «una petición con el token del USUARIO vino 401»: el servidor ya no reconoce la sesión. La emite
/// [ApiClient] (una vez por token) y la escucha el controlador de sesión para cerrarla también aquí. Vive en el
/// núcleo por la misma razón que la del kiosco.
final userUnauthorizedTickProvider = StateProvider<int>((ref) => 0);

/// Época de quien opera: cambia cada vez que cambia la persona detrás de la app. La mueven el controlador de sesión
/// (la sesión de usuario empieza o termina: se restaura, se entra, se sale o el servidor la revoca) y el del kiosco
/// (se identifica alguien distinto de quien dejó trabajo sin mandar; si vuelve la misma persona, no se mueve). Todo lo
/// que se deriva de quién opera —los repositorios y lo que se cargó con ellos, permisos, contexto con rol y sucursal,
/// carritos sin mandar, filtros— la vigila con `ref.watch`, así que se descarta en UN solo punto: quien entre después
/// en este aparato nunca ve lo del anterior. Vive en el núcleo, como las señales de 401, para que las features no
/// dependan de esos controladores. Lo del DISPOSITIVO (emparejamiento del kiosco, puente de impresión) no la vigila:
/// debe sobrevivir a cualquier cambio de persona.
final sessionEpochProvider = StateProvider<int>((ref) => 0);

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    ref.watch(tokenStorageProvider),
    ref.watch(sharedTerminalStorageProvider),
    () => ref.read(kioskUnauthorizedTickProvider.notifier).state++,
    () => ref.read(userUnauthorizedTickProvider.notifier).state++,
  ),
);

/// Nombre legible de ESTE aparato («Motorola moto g32 · Android 14») con el que se da de alta la sesión: es lo que
/// se ve en «Mis dispositivos». Se lee una sola vez: el aparato no cambia mientras la app corre.
final deviceNameProvider = FutureProvider<String>((ref) => readDeviceName());
