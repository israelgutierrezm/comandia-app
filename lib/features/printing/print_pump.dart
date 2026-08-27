import 'dart:io';

import 'package:dio/dio.dart';

import 'escpos.dart';

/// Lo que el pump necesita del almacenamiento. Abstracto para correrlo con dependencias simuladas en pruebas.
abstract class PrintStore {
  Future<String?> readToken();
  Future<String?> readCharset();
  Future<bool> isPrinted(String ulid);
  Future<void> markPrinted(String ulid);
}

/// Envío crudo a la impresora por TCP. Inyectable para pruebas.
typedef PrinterSender = Future<void> Function(String host, int port, List<int> bytes);

Future<void> tcpSend(String host, int port, List<int> bytes) async {
  Socket? socket;
  try {
    socket = await Socket.connect(host, port, timeout: const Duration(seconds: 8));
    socket.add(bytes);
    await socket.flush();
  } finally {
    await socket?.close();
    socket?.destroy();
  }
}

/// Un trabajo tal como lo entrega `jobs/next`.
class PrintJob {
  PrintJob({
    required this.ulid,
    required this.kindLabel,
    required this.connection,
    required this.target,
    required this.paperWidth,
    required this.payload,
    this.printerName,
  });

  final String ulid;
  final String kindLabel;

  /// `network` | `usb` | `windows_share`. La app solo puede con `network` (TCP a la LAN).
  final String connection;
  final String? target;
  final int? paperWidth;
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
      payload: (j['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
      printerName: printer?['name'] as String?,
    );
  }

  String get title => printerName == null ? kindLabel : '$kindLabel · $printerName';
}

/// Lo ocurrido con un trabajo, para el registro visible. Serializable porque cruza del isolate del servicio al de la UI.
class PumpEvent {
  PumpEvent(this.title, this.ok, this.detail);

  final String title;
  final bool ok;
  final String detail;

  Map<String, dynamic> toMap() => {'title': title, 'ok': ok, 'detail': detail};

  factory PumpEvent.fromMap(Map<dynamic, dynamic> m) =>
      PumpEvent('${m['title']}', m['ok'] == true, '${m['detail']}');
}

/// El token del agente no sirve o fue revocado (401/403): quien llama debe detenerse y avisar.
class PumpAuthError implements Exception {}

/// Otro código inesperado del servidor.
class PumpHttpError implements Exception {
  PumpHttpError(this.status);
  final int status;
}

/// El núcleo del puente: un ciclo de sondeo (reclamar → render ESC/POS → TCP → avisar). Sin Riverpod ni Flutter, así
/// corre igual en el isolate de la UI (botón «Probar ahora») que en el del servicio en primer plano, y se testea con
/// dependencias simuladas.
class PrintPump {
  PrintPump({required this.dio, required this.store, this.sender = tcpSend});

  final Dio dio;
  final PrintStore store;
  final PrinterSender sender;

  /// Ejecuta un ciclo y devuelve lo ocurrido. Lanza [PumpAuthError] con token inválido y [PumpHttpError] en otros
  /// códigos, para que quien llama decida (detener el servicio, mostrar el error).
  Future<List<PumpEvent>> cycle({int limit = 5}) async {
    final res = await dio.get('/print-agent/jobs/next', queryParameters: {'limit': limit});
    final status = res.statusCode ?? 0;
    if (status == 401 || status == 403) throw PumpAuthError();
    if (status != 200) throw PumpHttpError(status);

    final data = (res.data is Map ? res.data['data'] : null) as List? ?? const [];
    final charset = Charset.fromName(await store.readCharset());

    final events = <PumpEvent>[];
    for (final raw in data) {
      events.add(await _handle(PrintJob.fromJson((raw as Map).cast<String, dynamic>()), charset));
    }
    return events;
  }

  Future<PumpEvent> _handle(PrintJob job, Charset charset) async {
    try {
      // Idempotencia: si ya se imprimió (el aviso se perdió y el trabajo reapareció al expirar su reclamo), no se
      // reimprime; solo se reintenta avisar.
      if (await store.isPrinted(job.ulid)) {
        await _report(job.ulid, ok: true);
        return PumpEvent(job.title, true, 'Ya impreso; se reintentó el aviso');
      }
      if (job.connection != 'network') {
        await _report(job.ulid, ok: false, error: 'Conexión no soportada por la app: ${job.connection}. Solo red (LAN).');
        return PumpEvent(job.title, false, 'Solo imprime por red; es ${job.connection}');
      }
      final dest = (job.target ?? '').trim();
      if (dest.isEmpty) {
        await _report(job.ulid, ok: false, error: 'La impresora no tiene destino configurado.');
        return PumpEvent(job.title, false, 'Impresora sin destino');
      }
      final parts = dest.split(':');
      final host = parts.first;
      final port = parts.length > 1 ? (int.tryParse(parts[1]) ?? 9100) : 9100;

      final bytes = renderTicket(job.payload, paperWidth: job.paperWidth, charset: charset);
      await sender(host, port, bytes);
      // Se marca ANTES de avisar: si el aviso falla, la marca ya evita la reimpresión.
      await store.markPrinted(job.ulid);
      await _report(job.ulid, ok: true);
      return PumpEvent(job.title, true, 'Impreso');
    } on SocketException catch (e) {
      await _report(job.ulid, ok: false, error: 'No se pudo conectar a ${job.target} (${e.osError?.message ?? 'sin ruta'}).');
      return PumpEvent(job.title, false, 'No se pudo conectar');
    } catch (e) {
      await _report(job.ulid, ok: false, error: '$e');
      return PumpEvent(job.title, false, '$e');
    }
  }

  Future<void> _report(String ulid, {required bool ok, String? error}) async {
    try {
      if (ok) {
        await dio.post('/print-agent/jobs/$ulid/printed');
      } else {
        await dio.post('/print-agent/jobs/$ulid/failed', data: {'error': _clampError(error)});
      }
    } catch (_) {
      // Si el aviso falla, el servidor reofrece el trabajo al expirar el reclamo; la marca local evita reimprimir.
    }
  }

  /// El servidor exige el motivo entre 3 y 300 caracteres.
  String _clampError(String? error) {
    final msg = (error ?? '').trim();
    if (msg.length < 3) return 'Error desconocido';
    return msg.length > 300 ? msg.substring(0, 300) : msg;
  }
}
