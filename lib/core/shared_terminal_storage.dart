import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Guarda la credencial de la TERMINAL COMPARTIDA (ADR-014): el token del dispositivo y, para la
/// pantalla de bloqueo, el nombre de la terminal y la sucursal a las que quedó emparejado.
///
/// Es una credencial del DISPOSITIVO, no del usuario: sobrevive al «salir» del operador y al cierre de
/// sesión de usuario, igual que el token del agente de impresión. Mientras exista un token aquí, el
/// dispositivo es un kiosco y toda la API viaja con `X-Terminal-Token` (v. [ApiClient]).
class SharedTerminalStorage {
  const SharedTerminalStorage(this._storage);

  final FlutterSecureStorage _storage;

  static const _kToken = 'shared_terminal_token';
  static const _kTerminal = 'shared_terminal_name';
  static const _kBranch = 'shared_terminal_branch';

  Future<void> saveToken(String token) => _storage.write(key: _kToken, value: token.trim());
  Future<String?> readToken() => _storage.read(key: _kToken);
  Future<bool> hasToken() async {
    final t = await readToken();
    return t != null && t.isNotEmpty;
  }

  Future<void> saveLabels({String? terminalName, String? branchName}) async {
    await _storage.write(key: _kTerminal, value: terminalName);
    await _storage.write(key: _kBranch, value: branchName);
  }

  Future<String?> readTerminalName() => _storage.read(key: _kTerminal);
  Future<String?> readBranchName() => _storage.read(key: _kBranch);

  /// Desemparejar: olvida el token y las etiquetas. El dispositivo vuelve a ser uno normal (login de usuario).
  Future<void> clear() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kTerminal);
    await _storage.delete(key: _kBranch);
  }
}
