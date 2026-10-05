import 'dart:async';
import 'dart:convert';

import 'package:comandia_app/core/providers.dart';
import 'package:comandia_app/features/auth/auth.dart';
import 'package:comandia_app/features/home/home_shell.dart';
import 'package:comandia_app/features/printing/print_bridge.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Adaptador HTTP simulado. `handler` puede devolver un Future: así se simula un servidor que tarda en contestar.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);
  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      handler(options);
}

ResponseBody _json(Object body, int status) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

ResponseBody _empty(int status) => ResponseBody.fromString('', status);

/// El puente de impresión sin el servicio en primer plano, que es nativo y no existe en la prueba.
class _QuietBridge extends PrintBridge {
  @override
  BridgeState build() => const BridgeState();
}

/// Como el router: sin sesión, el acceso; con ella, la app.
class _App extends ConsumerWidget {
  const _App();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(authControllerProvider) == AuthStatus.unauthenticated ? const Text('Acceso') : const HomeShell();
}

void main() {
  // Almacenamiento seguro en memoria con una sesión de usuario abierta.
  final store = <String, String>{};

  setUp(() {
    store
      ..clear()
      ..['api_token'] = 'tok-1';
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = (call.arguments as Map?) ?? const {};
        final key = args['key'] as String?;
        switch (call.method) {
          case 'write':
            final value = args['value'] as String?;
            if (key != null) {
              value == null ? store.remove(key) : store[key] = value;
            }
            return null;
          case 'read':
            return key == null ? null : store[key];
          case 'delete':
            if (key != null) store.remove(key);
            return null;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  testWidgets('«Salir» se deshabilita y avisa que está cerrando sesión; un segundo toque no cierra dos veces',
      (tester) async {
    final revocations = <RequestOptions>[];
    final serverReply = Completer<ResponseBody>();
    final container = ProviderContainer(overrides: [printBridgeProvider.overrideWith(_QuietBridge.new)]);
    addTearDown(container.dispose);
    container.read(apiClientProvider).dio.httpClientAdapter = _FakeAdapter((o) {
      if (o.path == '/auth/token' && o.method == 'DELETE') {
        revocations.add(o);
        // El servidor tarda: mientras tanto la pantalla debe decir qué pasa.
        return serverReply.future;
      }
      if (o.path == '/context') return _json({'data': <String, dynamic>{}}, 200);
      return _json({'data': <Object>[]}, 200);
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MaterialApp(home: _App())),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final salir = find.byTooltip('Salir');
    // Dos toques seguidos, antes de que la pantalla alcance a redibujarse.
    await tester.tap(salir);
    await tester.tap(salir);
    await tester.pump();

    expect(find.text('Cerrando sesión…'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.logout)).onPressed, isNull);

    // Ya deshabilitado, tocarlo otra vez no hace nada.
    await tester.tap(salir, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(revocations, hasLength(1));

    // El servidor contesta: la sesión se cierra y la app vuelve al acceso.
    serverReply.complete(_empty(204));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(container.read(authControllerProvider), AuthStatus.unauthenticated);
    expect(find.text('Acceso'), findsOneWidget);
    expect(store.containsKey('api_token'), isFalse);
    expect(revocations, hasLength(1));
  });
}
