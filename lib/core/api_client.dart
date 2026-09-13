import 'package:dio/dio.dart';

import 'config.dart';
import 'shared_terminal_storage.dart';
import 'token_storage.dart';

/// Cliente HTTP contra `/api/v1`.
///
/// Un interceptor decide la credencial de cada petición:
///  - **Modo kiosco** (ADR-014): si hay un token de dispositivo, la identidad es el DISPOSITIVO — se
///    manda `X-Terminal-Token` y NADA del usuario. Así las mismas pantallas del POS operan como kiosco
///    sin cambiar una línea: basta que el dispositivo esté emparejado.
///  - **Usuario**: si no hay token de dispositivo, se manda `Authorization: Bearer` y, si los hay, el rol
///    y la sucursal activos (`X-Role`/`X-Branch`) — la convención de la SPA de Vue.
///
/// Cuando una petición del kiosco vuelve 401, el operador caducó en el servidor (inactividad) o el token
/// fue revocado: se avisa por [onDeviceUnauthorized] para que el kiosco vuelva al bloqueo, igual que el
/// manejador de 401 del kiosco web.
class ApiClient {
  ApiClient(
    this._storage, [
    this._sharedTerminal,
    this.onDeviceUnauthorized,
  ]) : dio = Dio(
          BaseOptions(
            baseUrl: AppConfig.apiV1,
            headers: {'Accept': 'application/json'},
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 20),
            // La app maneja los errores por código; no queremos que Dio lance en 4xx.
            validateStatus: (status) => status != null && status < 500,
          ),
        ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final deviceToken = await _sharedTerminal?.readToken();

          if (deviceToken != null && deviceToken.isNotEmpty) {
            // Modo kiosco: sólo el token del dispositivo. No se mezcla con la credencial del usuario.
            options.headers['X-Terminal-Token'] = deviceToken;
            handler.next(options);
            return;
          }

          final token = await _storage.readToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }

          final role = await _storage.readRole();
          if (role != null) options.headers['X-Role'] = role;

          final branch = await _storage.readBranch();
          if (branch != null) options.headers['X-Branch'] = branch;

          handler.next(options);
        },
        onResponse: (response, handler) async {
          // 401 en modo kiosco = el operador caducó o el token se revocó → de vuelta al bloqueo.
          if (response.statusCode == 401 && onDeviceUnauthorized != null) {
            final deviceToken = await _sharedTerminal?.readToken();
            if (deviceToken != null && deviceToken.isNotEmpty) {
              onDeviceUnauthorized!();
            }
          }
          handler.next(response);
        },
      ),
    );
  }

  final Dio dio;
  final TokenStorage _storage;
  final SharedTerminalStorage? _sharedTerminal;

  /// Se invoca cuando una petición del kiosco vuelve 401 (operador caducado o token revocado).
  final void Function()? onDeviceUnauthorized;
}
