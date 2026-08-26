/// Configuración de la app.
///
/// La base de la API se puede sobreescribir al compilar con
/// `--dart-define=API_BASE_URL=https://...`. El valor por omisión sirve para el
/// EMULADOR de Android, donde `10.0.2.2` es el `localhost` de la máquina que
/// corre el servidor de Comandia (en `:8099`). En el simulador de iOS usa
/// `http://localhost:8099`; en un dispositivo físico, la IP de tu red local.
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8099',
  );

  static String get apiV1 => '$apiBaseUrl/api/v1';
}
