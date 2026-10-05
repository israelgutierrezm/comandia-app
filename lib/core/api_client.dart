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
///
/// Cuando una petición que llevó el token del USUARIO vuelve 401, el servidor ya no reconoce esa sesión (se
/// revocó desde «Mis dispositivos», la revocó un administrador, cambió la contraseña o caducó por desuso): se
/// avisa por [onUserUnauthorized], una sola vez por token, para que la app cierre la sesión local y vuelva al
/// acceso. No cuentan los canjes de credencial (iniciar/cerrar sesión, emparejar el kiosco): ahí un 401 es una
/// contraseña o un secreto equivocados, o un token que ya estaba revocado, no una sesión que se cayó.
class ApiClient {
  ApiClient(
    this._storage, [
    this._sharedTerminal,
    this.onDeviceUnauthorized,
    this.onUserUnauthorized,
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
            // Se anota QUÉ token viajó: al volver, un 401 sólo cierra la sesión si es de la sesión actual.
            options.extra[_kUserToken] = token;
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
          // 401 con el token del usuario = la sesión se revocó en el servidor → se cierra también aquí.
          if (response.statusCode == 401 && onUserUnauthorized != null) {
            await _userUnauthorized(response.requestOptions);
          }
          handler.next(response);
        },
      ),
    );
  }

  /// La credencial del USUARIO: `POST` la canjea por correo y contraseña (iniciar sesión) y `DELETE` revoca la
  /// que viaja en la petición (cerrar sesión).
  static const authTokenPath = '/auth/token';

  /// Canjes de credencial: su 401 habla de lo que se canjea (la contraseña, el secreto del dispositivo) o, al
  /// cerrar sesión, de un token que ya estaba revocado; nunca de que la sesión del usuario se cayó.
  static const _credentialPaths = {authTokenPath, '/shared-terminal/token'};

  static const _kUserToken = 'comandia.user_token';

  final Dio dio;
  final TokenStorage _storage;
  final SharedTerminalStorage? _sharedTerminal;

  /// Se invoca cuando una petición del kiosco vuelve 401 (operador caducado o token revocado).
  final void Function()? onDeviceUnauthorized;

  /// Se invoca cuando una petición con el token del usuario vuelve 401 (sesión revocada). Una vez por token.
  final void Function()? onUserUnauthorized;

  /// El último token del usuario cuyo 401 ya se avisó.
  String? _revokedUserToken;

  Future<void> _userUnauthorized(RequestOptions request) async {
    final sent = request.extra[_kUserToken];
    // Sin token del usuario (aún no hay sesión, o viajó el del kiosco) no hay sesión que cerrar.
    if (sent is! String || _credentialPaths.contains(request.path)) return;

    // Una pantalla suele lanzar varias peticiones a la vez y todas vuelven 401: se avisa UNA vez. La marca va
    // antes de cualquier await para que las respuestas concurrentes no se cuelen.
    if (sent == _revokedUserToken) return;
    _revokedUserToken = sent;

    // Una respuesta tardía de una sesión anterior (se salió y se volvió a entrar) no tumba la sesión nueva.
    if (await _storage.readToken() != sent) return;
    onUserUnauthorized!();
  }
}
