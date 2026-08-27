import 'package:dio/dio.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'escpos.dart';
import 'print_agent.dart';
import 'print_pump.dart';
import 'print_service.dart';

final printAgentStorageProvider = Provider<PrintAgentStorage>(
  (ref) => PrintAgentStorage(ref.watch(secureStorageProvider)),
);

final printAgentClientProvider = Provider<PrintAgentClient>(
  (ref) => PrintAgentClient(ref.watch(printAgentStorageProvider)),
);

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
    this.charset = Charset.cp850,
    this.log = const [],
    this.lastError,
  });

  final bool active;
  final bool hasToken;
  final bool busy;
  final Charset charset;
  final List<JobLog> log;
  final String? lastError;

  BridgeState copyWith({
    bool? active,
    bool? hasToken,
    bool? busy,
    Charset? charset,
    List<JobLog>? log,
    String? lastError,
    bool clearError = false,
  }) =>
      BridgeState(
        active: active ?? this.active,
        hasToken: hasToken ?? this.hasToken,
        busy: busy ?? this.busy,
        charset: charset ?? this.charset,
        log: log ?? this.log,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );
}

/// El puente de impresión. La estación desatendida corre en un **servicio en primer plano** (isolate aparte que el SO
/// no congela); este controlador lo arranca/detiene y refleja el registro que el servicio le manda. «Probar ahora»
/// corre un ciclo en primer plano, sin el servicio, para confirmar la conexión.
class PrintBridge extends Notifier<BridgeState> {
  bool _cycleRunning = false;

  @override
  BridgeState build() {
    // El servicio vive en otro isolate; manda sus eventos por aquí.
    FlutterForegroundTask.addTaskDataCallback(_onServiceData);
    ref.onDispose(() => FlutterForegroundTask.removeTaskDataCallback(_onServiceData));
    _loadSettings();
    return const BridgeState();
  }

  void _onServiceData(Object data) {
    if (data is! Map) return;
    if (data['error'] != null) {
      state = state.copyWith(lastError: '${data['error']}', active: false);
      return;
    }
    final e = PumpEvent.fromMap(data);
    _push(e.title, e.ok, e.detail);
    state = state.copyWith(clearError: true);
  }

  Future<void> _loadSettings() async {
    final store = ref.read(printAgentStorageProvider);
    final token = await store.readToken();
    final charset = Charset.fromName(await store.readCharset());
    final running = await FlutterForegroundTask.isRunningService;
    state = state.copyWith(hasToken: token != null && token.isNotEmpty, charset: charset, active: running);
  }

  Future<void> saveToken(String token) async {
    await ref.read(printAgentStorageProvider).saveToken(token);
    state = state.copyWith(hasToken: token.trim().isNotEmpty, clearError: true);
  }

  Future<void> forget() async {
    await stop();
    await ref.read(printAgentStorageProvider).clear();
    state = state.copyWith(hasToken: false);
  }

  Future<void> setCharset(Charset charset) async {
    await ref.read(printAgentStorageProvider).saveCharset(charset.name);
    state = state.copyWith(charset: charset);
  }

  /// Arranca el servicio en primer plano: sigue imprimiendo aunque la pantalla se apague o la app pase a segundo plano.
  Future<void> start() async {
    if (!state.hasToken || await FlutterForegroundTask.isRunningService) return;

    // Permisos: notificación (Android 13+) —sin ella no hay servicio en primer plano— y, en lo posible, salir del
    // ahorro de batería para que el SO no mate la estación.
    if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'comandia_print_bridge',
        channelName: 'Impresión Comandia',
        channelDescription: 'Mantiene la impresión activa mientras la estación está encendida.',
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(4000),
        allowWakeLock: true,
        allowWifiLock: true,
        autoRunOnBoot: false,
      ),
    );

    final result = await FlutterForegroundTask.startService(
      serviceId: 8099,
      serviceTypes: [ForegroundServiceTypes.dataSync],
      notificationTitle: 'Comandia · imprimiendo',
      notificationText: 'La estación está lista para imprimir.',
      callback: startPrintCallback,
    );

    if (result is ServiceRequestSuccess) {
      state = state.copyWith(active: true, clearError: true);
    } else {
      state = state.copyWith(lastError: 'No se pudo iniciar el servicio de impresión (revisa el permiso de notificaciones).');
    }
  }

  Future<void> stop() async {
    await FlutterForegroundTask.stopService();
    state = state.copyWith(active: false, busy: false);
  }

  /// «Probar ahora»: un ciclo en primer plano, sin el servicio. Confirma token, conexión e impresión.
  Future<void> poll() async {
    if (_cycleRunning || !state.hasToken) return;
    _cycleRunning = true;
    state = state.copyWith(busy: true);
    try {
      final pump = PrintPump(
        dio: ref.read(printAgentClientProvider).dio,
        store: ref.read(printAgentStorageProvider),
      );
      for (final e in await pump.cycle()) {
        _push(e.title, e.ok, e.detail);
      }
      state = state.copyWith(clearError: true);
    } on PumpAuthError {
      state = state.copyWith(lastError: 'El token del agente no es válido o fue revocado. Vuelve a capturarlo.');
    } on PumpHttpError catch (e) {
      state = state.copyWith(lastError: 'El servidor respondió ${e.status}.');
    } on DioException catch (e) {
      state = state.copyWith(lastError: 'No se pudo contactar al servidor (${e.type.name}).');
    } catch (e) {
      state = state.copyWith(lastError: '$e');
    } finally {
      _cycleRunning = false;
      state = state.copyWith(busy: false);
    }
  }

  void _push(String title, bool ok, String detail) {
    state = state.copyWith(log: [JobLog(title: title, ok: ok, detail: detail, at: DateTime.now()), ...state.log].take(30).toList());
  }
}

final printBridgeProvider = NotifierProvider<PrintBridge, BridgeState>(PrintBridge.new);
