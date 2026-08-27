import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Puerto de comunicación con el isolate del servicio de impresión (recibe sus eventos). Debe iniciarse antes de runApp.
  FlutterForegroundTask.initCommunicationPort();
  runApp(const ProviderScope(child: ComandiaApp()));
}

class ComandiaApp extends ConsumerWidget {
  const ComandiaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Comandia',
      debugShowCheckedModeBanner: false,
      theme: comandiaTheme,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
