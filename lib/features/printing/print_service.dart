import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'print_agent.dart';
import 'print_pump.dart';

/// Punto de entrada del isolate del servicio. Debe ser función de nivel superior y marcada `vm:entry-point` para que
/// sobreviva al tree-shaking: el SO la invoca en un isolate nuevo, sin la memoria de la UI.
@pragma('vm:entry-point')
void startPrintCallback() {
  FlutterForegroundTask.setTaskHandler(PrintTaskHandler());
}

/// Corre el ciclo del puente en el servicio en primer plano: sigue vivo con la pantalla apagada o la app en segundo
/// plano. El isolate es aparte, así que arma su propio almacenamiento y cliente (no comparte los de la UI) y devuelve
/// lo ocurrido al isolate principal con `sendDataToMain`.
class PrintTaskHandler extends TaskHandler {
  PrintPump? _pump;
  bool _running = false;
  int _printed = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    const storage = PrintAgentStorage(FlutterSecureStorage());
    final client = PrintAgentClient(storage);
    _pump = PrintPump(dio: client.dio, store: storage);
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // onRepeatEvent es síncrono; el ciclo es asíncrono. Se lanza sin esperar y `_running` evita solaparlos.
    _tick();
  }

  Future<void> _tick() async {
    final pump = _pump;
    if (pump == null || _running) return;
    _running = true;
    try {
      final events = await pump.cycle();
      for (final e in events) {
        if (e.ok) _printed++;
        FlutterForegroundTask.sendDataToMain(e.toMap());
      }
      if (events.isNotEmpty) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'Comandia · imprimiendo',
          notificationText: '$_printed impreso(s) en esta sesión.',
        );
      }
    } on PumpAuthError {
      // Token inválido: no tiene sentido seguir sondeando. Se avisa a la UI y se detiene el servicio.
      FlutterForegroundTask.sendDataToMain({'error': 'El token del agente no es válido o fue revocado. Vuelve a capturarlo.'});
      await FlutterForegroundTask.stopService();
    } catch (_) {
      // Errores de red transitorios: se reintenta en el siguiente tick, sin ruido en la notificación.
    } finally {
      _running = false;
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _pump = null;
  }
}
