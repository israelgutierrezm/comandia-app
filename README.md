# Comandia · App

App móvil de **Comandia** (Flutter). Iteración 9 de la hoja de ruta: supervisión → captura en tableta → puente de impresión.

Consume la misma **API v1** del monolito (`/api/v1`) y se autentica por **token** (Sanctum): el login pide un token y el token lleva su negocio (`tenant_id`) y su membresía (D69). El rol y la sucursal activos viajan como cabeceras `X-Role`/`X-Branch`, que el servidor revalida.

## Estado

Los tres roles de la Iteración 9 están completos:

- **Supervisión** — contexto de sesión, caja abierta del turno y su corte, turnos y reportes.
- **Caja** — abrir turno (terminal + fondo, gerente) y cerrar turno (declarar efectivo por método → cierre → corte).
- **Captura** — abrir cuenta **en mesa** (salón por zonas) o para llevar, marcado de 1 toque, comandar.
- **Cobro** — pagar una cuenta (uno o varios métodos, recibido/cambio, referencia, propina); al saldar, Comandia emite el ticket final que imprime por el puente.
- **Puente de impresión** — la app como agente ESC/POS: sondea trabajos y los manda por TCP a las impresoras de red. Con **páginas de códigos** (CP850/CP1252/ASCII), **idempotencia** (no reimprime un trabajo ya impreso) y **estación desatendida** (servicio en primer plano: sigue imprimiendo con la pantalla apagada o la app en segundo plano).

## Arquitectura

- **Estado:** Riverpod (`Notifier` / `AsyncNotifier`, sin generación de código).
- **HTTP:** `dio`, con un interceptor que añade `Authorization: Bearer` y `X-Role`/`X-Branch`.
- **Token:** `flutter_secure_storage` (Keychain / Keystore).
- **Navegación:** `go_router`, con redirección según haya sesión.
- **Por feature:** `lib/features/{auth,supervision,sessions,reports,pos,printing}`; infraestructura en `lib/core`.

## Puente de impresión (estación)

Convierte un dispositivo Android en un **agente de impresión** para una sucursal:

1. En el administrador de Comandia: **Impresoras → Agentes de impresión → Nuevo agente**. Copia el **token** (se ve una sola vez).
2. En la app: pestaña **Impresión → Guardar token**, elige la **página de códigos** y activa el **Puente**.

Con el puente activo corre un **servicio en primer plano** (`flutter_foreground_task`) con notificación persistente: el sondeo sigue vivo aunque la pantalla se apague o la app pase a segundo plano. El núcleo del ciclo vive en `PrintPump` (sin Flutter), reutilizado por el servicio y por «Probar ahora».

- **Solo imprime por red** (`network`, TCP a `IP:puerto`). `usb`/`windows_share` se reportan como fallo con mensaje: un móvil no los alcanza.
- **iOS** no tiene servicio real en segundo plano (el sistema mata los sockets): ahí el puente funciona **solo en primer plano**. El objetivo son estaciones Android.
- **Pendiente de verificar en dispositivo físico:** el servicio en primer plano no se prueba en `flutter test`. La lógica (`PrintPump`, páginas de códigos, idempotencia) sí está cubierta por pruebas.

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
