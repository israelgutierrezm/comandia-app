import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Guarda la credencial de la app de forma segura (Keychain en iOS, Keystore en
/// Android). Junto al token se guardan el rol y la sucursal ACTIVOS: el token
/// lleva el negocio (D69), pero el rol y la sucursal viajan como cabeceras
/// `X-Role`/`X-Branch` en cada llamada, y el servidor los revalida.
class TokenStorage {
  const TokenStorage(this._storage);

  final FlutterSecureStorage _storage;

  static const _kToken = 'api_token';
  static const _kRole = 'role_ulid';
  static const _kBranch = 'branch_ulid';

  Future<void> saveToken(String token) => _storage.write(key: _kToken, value: token);

  Future<void> saveContext({String? roleUlid, String? branchUlid}) async {
    await _storage.write(key: _kRole, value: roleUlid);
    await _storage.write(key: _kBranch, value: branchUlid);
  }

  Future<String?> readToken() => _storage.read(key: _kToken);
  Future<String?> readRole() => _storage.read(key: _kRole);
  Future<String?> readBranch() => _storage.read(key: _kBranch);

  Future<void> clear() => _storage.deleteAll();
}
