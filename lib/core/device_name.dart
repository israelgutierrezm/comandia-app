import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// El nombre cuando no se puede leer nada del aparato.
const fallbackDeviceName = 'App Comandia';

/// El servidor acepta a lo más 120 caracteres en `device_name`.
const maxDeviceNameLength = 120;

/// Arma el nombre con el que ESTE aparato da de alta su sesión (`device_name` de `POST auth/token`): marca + modelo +
/// sistema + versión, p. ej. «Motorola moto g32 · Android 14» o «Apple iPhone 13 · iOS 17.5». Es lo que la persona ve
/// en «Mis dispositivos» para reconocer —y revocar— cada sesión abierta. Es pura (sin plataforma) para poder probarla.
///
/// - Limpia los espacios de cada parte (orillas y repetidos).
/// - No repite la marca cuando el modelo ya empieza con ella («Redmi» + «Redmi Note 8» → «Redmi Note 8»).
/// - Capitaliza la marca sólo si viene toda en minúsculas («motorola» → «Motorola»; «iQOO» se respeta).
/// - Sin nombre de sistema se omite la versión: un «14» suelto no dice nada.
/// - Sin ningún dato devuelve [fallbackDeviceName]; si pasa de [maxDeviceNameLength], se recorta con «…».
String formatDeviceName({String? brand, String? model, String? osName, String? osVersion}) {
  final device = _merge(_capitalize(_clean(brand)), _clean(model));
  final os = _clean(osName);
  final system = os.isEmpty ? '' : _merge(os, _clean(osVersion));

  final name = [device, system].where((part) => part.isNotEmpty).join(' · ');
  if (name.isEmpty) return fallbackDeviceName;

  // Se cuenta por puntos de código, como el `max:120` del servidor (no por unidades UTF-16).
  final runes = name.runes;
  if (runes.length <= maxDeviceNameLength) return name;
  final cut = String.fromCharCodes(runes.take(maxDeviceNameLength - 1)).replaceFirst(RegExp(r'[\s·]+$'), '');
  return '$cut…';
}

/// Lee marca, modelo y sistema de ESTE aparato y los pasa por [formatDeviceName]. Nunca lanza: si la plataforma no
/// responde (o no es Android ni iOS), devuelve [fallbackDeviceName] — un nombre genérico no debe impedir entrar.
Future<String> readDeviceName() async {
  final info = DeviceInfoPlugin();
  try {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final android = await info.androidInfo;
        return formatDeviceName(
          brand: android.brand,
          model: android.model,
          osName: 'Android',
          osVersion: android.version.release,
        );
      case TargetPlatform.iOS:
        final ios = await info.iosInfo;
        // `modelName` es el nombre comercial («iPhone 13»); `model` sólo diría «iPhone».
        return formatDeviceName(
          brand: 'Apple',
          model: ios.modelName,
          osName: ios.systemName,
          osVersion: ios.systemVersion,
        );
      default:
        return fallbackDeviceName;
    }
  } catch (_) {
    return fallbackDeviceName;
  }
}

String _clean(String? value) => (value ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

String _capitalize(String value) =>
    value.isNotEmpty && value == value.toLowerCase() ? '${value[0].toUpperCase()}${value.substring(1)}' : value;

/// Une `head` y `tail` con un espacio, salvo que `tail` ya empiece con `head` como palabra completa: entonces basta
/// `tail`. «Redmi» + «Redmi Note 8» → «Redmi Note 8»; pero «LG» + «LGM-V300K» → «LG LGM-V300K» (ahí es parte del código).
String _merge(String head, String tail) {
  if (head.isEmpty) return tail;
  if (tail.isEmpty) return head;

  final repeats = tail.length >= head.length &&
      tail.substring(0, head.length).toLowerCase() == head.toLowerCase() &&
      (tail.length == head.length || !RegExp('[A-Za-z0-9]').hasMatch(tail[head.length]));

  return repeats ? tail : '$head $tail';
}
