import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';

/// Un fallo de acceso con mensaje para mostrar (credenciales, cuenta inactiva…).
class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TenantOption {
  TenantOption(this.ulid, this.name);
  final String ulid;
  final String name;
}

/// La persona pertenece a varios negocios: hay que reintentar eligiendo uno.
class NeedTenantSelection implements Exception {
  NeedTenantSelection(this.options);
  final List<TenantOption> options;
}

class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  /// Devuelve el token en claro. Lanza [AuthException] o [NeedTenantSelection].
  Future<String> login({
    required String email,
    required String password,
    required String deviceName,
    String? tenantUlid,
  }) async {
    final res = await _api.dio.post<dynamic>('/auth/token', data: {
      'email': email,
      'password': password,
      'device_name': deviceName,
      'tenant_ulid': ?tenantUlid,
    });

    final status = res.statusCode ?? 0;
    final data = res.data;

    if (status == 201 && data is Map && data['token'] is String) {
      return data['token'] as String;
    }

    if (status == 409 && data is Map && data['memberships'] is List) {
      final options = (data['memberships'] as List)
          .map((m) => TenantOption(m['tenant_ulid'] as String, m['tenant_name'] as String))
          .toList();
      throw NeedTenantSelection(options);
    }

    throw AuthException(_firstError(data) ?? 'No se pudo iniciar sesión.');
  }

  String? _firstError(dynamic data) {
    if (data is Map && data['errors'] is Map) {
      for (final value in (data['errors'] as Map).values) {
        if (value is List && value.isNotEmpty) return value.first.toString();
      }
    }
    if (data is Map && data['message'] is String) return data['message'] as String;
    return null;
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);

enum AuthStatus { unknown, authenticated, unauthenticated }

/// Gobierna si hay sesión. Al arrancar restaura desde el token guardado; el
/// router escucha este estado para mandar al acceso o a la app.
class AuthController extends Notifier<AuthStatus> {
  @override
  AuthStatus build() {
    _restore();
    return AuthStatus.unknown;
  }

  Future<void> _restore() async {
    final token = await ref.read(tokenStorageProvider).readToken();
    state = token == null ? AuthStatus.unauthenticated : AuthStatus.authenticated;
  }

  Future<void> login({
    required String email,
    required String password,
    String? tenantUlid,
  }) async {
    final token = await ref.read(authRepositoryProvider).login(
          email: email,
          password: password,
          deviceName: 'App Comandia',
          tenantUlid: tenantUlid,
        );

    await ref.read(tokenStorageProvider).saveToken(token);
    state = AuthStatus.authenticated;
  }

  Future<void> logout() async {
    await ref.read(tokenStorageProvider).clear();
    state = AuthStatus.unauthenticated;
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthStatus>(AuthController.new);
