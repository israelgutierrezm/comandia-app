import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/shared_terminal_storage.dart';

/// El secreto de emparejamiento no sirvió (no existe, revocado, o la terminal ya no es compartida).
class PairError implements Exception {
  PairError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// La identificación por PIN falló (código/PIN incorrectos) o el PIN quedó bloqueado.
class IdentifyError implements Exception {
  IdentifyError(this.message, {this.locked = false});
  final String message;
  final bool locked;
  @override
  String toString() => message;
}

/// A qué quedó emparejado el dispositivo (para la pantalla de bloqueo).
class PairedTerminal {
  PairedTerminal({this.terminalName, this.branchName});
  final String? terminalName;
  final String? branchName;
}

/// Consume la superficie por TOKEN de la terminal compartida (ADR-014): emparejar el dispositivo,
/// identificar al operador por PIN y salir. El token del dispositivo lo guarda y lo reenvía [ApiClient];
/// aquí sólo se escribe/borra en el almacenamiento y se traducen los códigos del servidor a excepciones.
class SharedTerminalRepository {
  SharedTerminalRepository(this._api, this._storage);

  final ApiClient _api;
  final SharedTerminalStorage _storage;

  /// Canjea el secreto `{ulid}|{token}` por un token de dispositivo y lo guarda. Lanza [PairError].
  Future<PairedTerminal> pair(String secret) async {
    final res = await _api.dio.post<dynamic>('/shared-terminal/token', data: {'secret': secret.trim()});

    final data = res.data;
    if (res.statusCode == 200 && data is Map && data['token'] is String) {
      final device = data['data'];
      final branch = data['branch'];
      final terminalName = device is Map && device['terminal'] is Map ? device['terminal']['name'] as String? : null;
      final branchName = branch is Map ? branch['name'] as String? : null;

      await _storage.saveToken(data['token'] as String);
      await _storage.saveLabels(terminalName: terminalName, branchName: branchName);

      return PairedTerminal(terminalName: terminalName, branchName: branchName);
    }

    throw PairError(_title(data) ?? 'El secreto no es válido o la terminal ya no está compartida.');
  }

  /// Identifica al operador por código de empleado + PIN. Lanza [IdentifyError] (422 incorrecto, 423 bloqueado).
  Future<void> identify({required String employeeCode, required String pin}) async {
    final res = await _api.dio.post<dynamic>('/shared-terminal/token/operator', data: {
      'employee_code': employeeCode.trim(),
      'pin': pin.trim(),
    });

    final status = res.statusCode ?? 0;
    if (status == 204) return;

    if (status == 423) {
      throw IdentifyError(_title(res.data) ?? 'PIN bloqueado por demasiados intentos. Espera unos minutos.', locked: true);
    }

    throw IdentifyError(_title(res.data) ?? 'Código de empleado o PIN incorrectos.');
  }

  /// Salir: olvida al operador en el servidor. Mejor esfuerzo — un fallo de red no debe atorar el bloqueo.
  Future<void> release() async {
    try {
      await _api.dio.delete<dynamic>('/shared-terminal/token/operator');
    } catch (_) {
      // El bloqueo local es la verdad para la UI; el servidor también caduca al operador por inactividad.
    }
  }

  /// Desempareja el dispositivo (borra el token local). No toca el servidor: la credencial se revoca desde
  /// la administración (aparato perdido); esto sólo deja de usarlo como kiosco en ESTE aparato.
  Future<void> unpair() => _storage.clear();

  String? _title(dynamic data) {
    if (data is Map && data['title'] is String) return data['title'] as String;
    if (data is Map && data['errors'] is Map) {
      for (final v in (data['errors'] as Map).values) {
        if (v is List && v.isNotEmpty) return v.first.toString();
      }
    }
    return null;
  }
}

final sharedTerminalRepositoryProvider = Provider<SharedTerminalRepository>(
  (ref) => SharedTerminalRepository(
    ref.watch(apiClientProvider),
    ref.watch(sharedTerminalStorageProvider),
  ),
);

/// Etiquetas del emparejamiento (terminal y sucursal) para la pantalla de bloqueo.
final kioskLabelsProvider = FutureProvider<PairedTerminal>((ref) async {
  final s = ref.watch(sharedTerminalStorageProvider);
  return PairedTerminal(terminalName: await s.readTerminalName(), branchName: await s.readBranchName());
});

/// El estado del kiosco: sin emparejar, en el bloqueo (emparejado, sin operador) u operando.
enum KioskStatus { unknown, unpaired, locked, operating }

/// Gobierna el modo kiosco. Al arrancar restaura desde el token del dispositivo; el router escucha este
/// estado (junto al de sesión) para mandar al emparejamiento, al bloqueo o al POS.
class KioskController extends Notifier<KioskStatus> {
  @override
  KioskStatus build() {
    // Si una petición del kiosco vino 401 mientras se operaba, el operador caducó: de vuelta al bloqueo.
    ref.listen(kioskUnauthorizedTickProvider, (_, _) {
      if (state == KioskStatus.operating) state = KioskStatus.locked;
    });

    _restore();
    return KioskStatus.unknown;
  }

  Future<void> _restore() async {
    final paired = await ref.read(sharedTerminalStorageProvider).hasToken();
    // Al arrancar, un dispositivo emparejado empieza en el BLOQUEO: siempre se re-teclea el PIN.
    state = paired ? KioskStatus.locked : KioskStatus.unpaired;
  }

  /// Empareja el dispositivo con el secreto de enrolamiento. Lanza [PairError].
  Future<void> pair(String secret) async {
    await ref.read(sharedTerminalRepositoryProvider).pair(secret);
    ref.invalidate(kioskLabelsProvider);
    state = KioskStatus.locked;
  }

  /// Identifica al operador por PIN → a operar. Lanza [IdentifyError].
  Future<void> identify({required String employeeCode, required String pin}) async {
    await ref.read(sharedTerminalRepositoryProvider).identify(employeeCode: employeeCode, pin: pin);
    state = KioskStatus.operating;
  }

  /// Salir: vuelve al bloqueo (el dispositivo permanece emparejado).
  Future<void> lock() async {
    await ref.read(sharedTerminalRepositoryProvider).release();
    state = KioskStatus.locked;
  }

  /// Desemparejar este aparato como kiosco (vuelve al login de usuario).
  Future<void> unpair() async {
    await ref.read(sharedTerminalRepositoryProvider).unpair();
    state = KioskStatus.unpaired;
  }
}

final kioskControllerProvider = NotifierProvider<KioskController, KioskStatus>(KioskController.new);
