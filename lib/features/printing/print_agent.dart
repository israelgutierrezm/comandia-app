import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/config.dart';
import 'print_pump.dart';

/// Almacenamiento del agente de impresión — token, página de códigos y registro de impresos. Credencial aparte de la
/// del usuario: sobrevive al cierre de sesión. Implementa [PrintStore] para que el pump lo use en cualquier isolate.
class PrintAgentStorage implements PrintStore {
  const PrintAgentStorage(this._storage);

  final FlutterSecureStorage _storage;
  static const _kToken = 'print_agent_token';
  static const _kCharset = 'print_charset';
  static const _kPrinted = 'printed_jobs';

  Future<void> saveToken(String token) => _storage.write(key: _kToken, value: token.trim());
  @override
  Future<String?> readToken() => _storage.read(key: _kToken);
  Future<void> clear() => _storage.delete(key: _kToken);

  Future<void> saveCharset(String name) => _storage.write(key: _kCharset, value: name);
  @override
  Future<String?> readCharset() => _storage.read(key: _kCharset);

  // Registro de trabajos ya impresos (idempotencia). Ordenado, el más reciente primero, con tope.
  Future<List<String>> _printedList() async {
    final raw = await _storage.read(key: _kPrinted);
    return (raw == null || raw.isEmpty) ? <String>[] : raw.split(',').where((e) => e.isNotEmpty).toList();
  }

  @override
  Future<bool> isPrinted(String ulid) async => (await _printedList()).contains(ulid);

  @override
  Future<void> markPrinted(String ulid) async {
    final list = await _printedList();
    if (list.contains(ulid)) return;
    // Se conservan los últimos 300: cubre la ventana de un reclamo, acotado para no crecer sin fin.
    final next = [ulid, ...list].take(300).toList();
    await _storage.write(key: _kPrinted, value: next.join(','));
  }
}

/// Cliente contra `/api/v1/print-agent/*`. Manda el token del agente en la cabecera `X-Print-Agent-Token`, que lee del
/// almacenamiento en cada petición (misma disciplina que el cliente del usuario).
class PrintAgentClient {
  PrintAgentClient(this._storage)
      : dio = Dio(
          BaseOptions(
            baseUrl: AppConfig.apiV1,
            headers: {'Accept': 'application/json'},
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 20),
            validateStatus: (status) => status != null && status < 500,
          ),
        ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.readToken();
          if (token != null && token.isNotEmpty) {
            options.headers['X-Print-Agent-Token'] = token;
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio dio;
  final PrintAgentStorage _storage;
}
