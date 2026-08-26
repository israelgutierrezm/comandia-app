import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import 'escpos.dart';

/// Almacenamiento del token del AGENTE de impresión — distinto del token del usuario. El puente autentica con su propia
/// credencial (la emite el administrador del negocio) y sigue vivo aunque el usuario cierre su sesión.
class PrintAgentStorage {
  const PrintAgentStorage(this._storage);

  final FlutterSecureStorage _storage;
  static const _kToken = 'print_agent_token';

  Future<void> saveToken(String token) => _storage.write(key: _kToken, value: token.trim());
  Future<String?> readToken() => _storage.read(key: _kToken);
  Future<void> clear() => _storage.delete(key: _kToken);
}

final printAgentStorageProvider = Provider<PrintAgentStorage>(
  (ref) => PrintAgentStorage(ref.watch(secureStorageProvider)),
);

/// Cliente contra `/api/v1/print-agent/*`. Manda el token del agente en la cabecera `X-Print-Agent-Token`, que lee del
/// almacenamiento en cada petición (misma disciplina que [ApiClient] con el token del usuario).
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

final printAgentClientProvider = Provider<PrintAgentClient>(
  (ref) => PrintAgentClient(ref.watch(printAgentStorageProvider)),
);

/// Un trabajo de impresión tal como lo entrega `jobs/next`.
class PrintJob {
  PrintJob({
    required this.ulid,
    required this.kindLabel,
    required this.connection,
    required this.target,
    required this.paperWidth,
    required this.supportsCashDrawer,
    required this.payload,
    this.printerName,
  });

  final String ulid;
  final String kindLabel;

  /// `network` | `usb` | `windows_share`. Esta app solo puede con `network` (TCP a la LAN).
  final String connection;
  final String? target;
  final int? paperWidth;
  final bool supportsCashDrawer;
  final Map<String, dynamic> payload;
  final String? printerName;

  factory PrintJob.fromJson(Map<String, dynamic> j) {
    final printer = (j['printer'] as Map?)?.cast<String, dynamic>();
    return PrintJob(
      ulid: j['ulid'] as String,
      kindLabel: (j['kind_label'] ?? j['kind'] ?? 'Ticket').toString(),
      connection: (printer?['connection'] ?? 'network').toString(),
      target: printer?['target'] as String?,
      paperWidth: (printer?['paper_width'] as num?)?.toInt(),
      supportsCashDrawer: printer?['supports_cash_drawer'] == true,
      payload: (j['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
      printerName: printer?['name'] as String?,
    );
  }
}

/// Una entrada del registro visible del puente (últimas impresiones y fallos).
class JobLog {
  JobLog({required this.title, required this.ok, required this.detail, required this.at});

  final String title;
  final bool ok;
  final String detail;
  final DateTime at;
}

/// Estado del puente para la pantalla.
class BridgeState {
  const BridgeState({
    this.active = false,
    this.hasToken = false,
    this.busy = false,
    this.log = const [],
    this.lastError,
  });

  final bool active;
  final bool hasToken;
  final bool busy;
  final List<JobLog> log;
  final String? lastError;

  BridgeState copyWith({
    bool? active,
    bool? hasToken,
    bool? busy,
    List<JobLog>? log,
    String? lastError,
    bool clearError = false,
  }) =>
      BridgeState(
        active: active ?? this.active,
        hasToken: hasToken ?? this.hasToken,
        busy: busy ?? this.busy,
        log: log ?? this.log,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );
}

/// El puente de impresión: mientras está activo, un [Timer] sondea trabajos, los arma en ESC/POS y los manda por TCP a la
/// impresora de red; luego reporta al servidor `printed`/`failed`. Los efectos cruzados (marcar el trabajo) los decide el
/// servidor: la app solo imprime y avisa.
class PrintBridge extends Notifier<BridgeState> {
  Timer? _timer;
  bool _cycleRunning = false;

  static const _interval = Duration(seconds: 4);

  @override
  BridgeState build() {
    ref.onDispose(() => _timer?.cancel());
    _loadToken();
    return const BridgeState();
  }

  Future<void> _loadToken() async {
    final token = await ref.read(printAgentStorageProvider).readToken();
    state = state.copyWith(hasToken: token != null && token.isNotEmpty);
  }

  Future<void> saveToken(String token) async {
    await ref.read(printAgentStorageProvider).saveToken(token);
    state = state.copyWith(hasToken: token.trim().isNotEmpty, clearError: true);
  }

  Future<void> forget() async {
    stop();
    await ref.read(printAgentStorageProvider).clear();
    state = state.copyWith(hasToken: false);
  }

  void start() {
    if (state.active || !state.hasToken) return;
    state = state.copyWith(active: true, clearError: true);
    _timer = Timer.periodic(_interval, (_) => poll());
    poll(); // primer ciclo inmediato, sin esperar el intervalo
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    if (state.active) state = state.copyWith(active: false, busy: false);
  }

  /// Un ciclo del puente. Reentrante-seguro: si el anterior sigue corriendo, este regresa sin hacer nada.
  Future<void> poll() async {
    if (_cycleRunning) return;
    _cycleRunning = true;
    state = state.copyWith(busy: true);
    try {
      final dio = ref.read(printAgentClientProvider).dio;
      final res = await dio.get('/print-agent/jobs/next', queryParameters: {'limit': 5});

      if (res.statusCode == 401 || res.statusCode == 403) {
        state = state.copyWith(lastError: 'El token del agente no es válido o fue revocado. Vuelve a capturarlo.');
        stop();
        return;
      }
      if (res.statusCode != 200) {
        state = state.copyWith(lastError: 'El servidor respondió ${res.statusCode}.');
        return;
      }

      final data = (res.data is Map ? res.data['data'] : null) as List? ?? const [];
      for (final raw in data) {
        await _handle(PrintJob.fromJson((raw as Map).cast<String, dynamic>()));
      }
      state = state.copyWith(clearError: true);
    } on DioException catch (e) {
      state = state.copyWith(lastError: 'No se pudo contactar al servidor (${e.type.name}).');
    } catch (e) {
      state = state.copyWith(lastError: '$e');
    } finally {
      _cycleRunning = false;
      state = state.copyWith(busy: false);
    }
  }

  Future<void> _handle(PrintJob job) async {
    final title = job.printerName == null ? job.kindLabel : '${job.kindLabel} · ${job.printerName}';
    try {
      if (job.connection != 'network') {
        const msg = 'Esta app solo imprime por red (LAN).';
        await _report(job, ok: false, error: 'Conexión no soportada por la app: ${job.connection}. $msg');
        _push(title, false, '$msg (${job.connection})');
        return;
      }
      final bytes = renderTicket(job.payload, paperWidth: job.paperWidth);
      await _sendTcp(job.target, bytes);
      await _report(job, ok: true);
      _push(title, true, 'Impreso');
    } on _BridgeError catch (e) {
      await _report(job, ok: false, error: e.message);
      _push(title, false, e.message);
    } catch (e) {
      await _report(job, ok: false, error: '$e');
      _push(title, false, '$e');
    }
  }

  Future<void> _sendTcp(String? target, List<int> bytes) async {
    final dest = target?.trim() ?? '';
    if (dest.isEmpty) throw _BridgeError('La impresora no tiene destino configurado.');

    final parts = dest.split(':');
    final host = parts.first;
    final port = parts.length > 1 ? (int.tryParse(parts[1]) ?? 9100) : 9100;

    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: const Duration(seconds: 8));
      socket.add(bytes);
      await socket.flush();
    } on SocketException catch (e) {
      throw _BridgeError('No se pudo conectar a $host:$port (${e.osError?.message ?? 'sin ruta'}).');
    } finally {
      await socket?.close();
      socket?.destroy();
    }
  }

  Future<void> _report(PrintJob job, {required bool ok, String? error}) async {
    final dio = ref.read(printAgentClientProvider).dio;
    try {
      if (ok) {
        await dio.post('/print-agent/jobs/${job.ulid}/printed');
      } else {
        await dio.post('/print-agent/jobs/${job.ulid}/failed', data: {'error': _clampError(error)});
      }
    } catch (_) {
      // Si el reporte falla, el servidor mantiene el trabajo reclamado hasta que su reclamo expire y lo vuelve a
      // ofrecer; el puente lo reintentará. Perder el reporte no pierde el trabajo. (Deuda v1: puede reimprimir.)
    }
  }

  /// El servidor exige el motivo entre 3 y 300 caracteres.
  String _clampError(String? error) {
    final msg = (error ?? '').trim();
    if (msg.length < 3) return 'Error desconocido';
    return msg.length > 300 ? msg.substring(0, 300) : msg;
  }

  void _push(String title, bool ok, String detail) {
    final entry = JobLog(title: title, ok: ok, detail: detail, at: DateTime.now());
    state = state.copyWith(log: [entry, ...state.log].take(30).toList());
  }
}

class _BridgeError implements Exception {
  _BridgeError(this.message);
  final String message;
}

final printBridgeProvider = NotifierProvider<PrintBridge, BridgeState>(PrintBridge.new);
