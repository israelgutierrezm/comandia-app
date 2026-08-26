# Comandia · App

App móvil de **Comandia** (Flutter). Iteración 9 de la hoja de ruta: supervisión → captura en tableta → puente de impresión.

Consume la misma **API v1** del monolito (`/api/v1`) y se autentica por **token** (Sanctum): el login pide un token y el token lleva su negocio (`tenant_id`) y su membresía (D69). El rol y la sucursal activos viajan como cabeceras `X-Role`/`X-Branch`, que el servidor revalida.

## Estado

**Esqueleto que camina** (primer entregable): acceso por token → guardado seguro del token → una pantalla de **supervisión** real (contexto de sesión + caja abierta del turno y su corte). Valida toda la pila de punta a punta. Lo que sigue crece encima: supervisión completa → captura de pedidos → puente de impresión.

## Arquitectura

- **Estado:** Riverpod (`Notifier` / `AsyncNotifier`, sin generación de código).
- **HTTP:** `dio`, con un interceptor que añade `Authorization: Bearer` y `X-Role`/`X-Branch`.
- **Token:** `flutter_secure_storage` (Keychain / Keystore).
- **Navegación:** `go_router`, con redirección según haya sesión.
- **Por feature:** `lib/features/{auth,supervision}`; infraestructura en `lib/core`.

## Correr

Necesita el servidor de Comandia arriba. La base de la API se pasa al compilar:

```bash
# Emulador Android (10.0.2.2 = localhost del host):
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8099

# Simulador iOS o escritorio:
flutter run --dart-define=API_BASE_URL=http://localhost:8099

# Dispositivo físico: la IP de tu máquina en la red local, p. ej.:
flutter run --dart-define=API_BASE_URL=http://192.168.1.50:8099
```

Sin `--dart-define`, la base por omisión es `http://10.0.2.2:8099` (emulador Android).

Acceso de demostración (con el negocio sembrado en Comandia): `demo@comandia.test` / `comandia`.

## Verificar

```bash
flutter analyze
flutter test
```
