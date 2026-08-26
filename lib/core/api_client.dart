import 'package:dio/dio.dart';

import 'config.dart';
import 'token_storage.dart';

/// Cliente HTTP contra `/api/v1`. Un interceptor pone en cada petición el token
/// (`Authorization: Bearer`) y, si los hay, el rol y la sucursal activos
/// (`X-Role`/`X-Branch`) — la misma convención que usa la SPA de Vue.
class ApiClient {
  ApiClient(this._storage)
      : dio = Dio(
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
      ),
    );
  }

  final Dio dio;
  final TokenStorage _storage;
}
