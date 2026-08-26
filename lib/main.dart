import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme.dart';

void main() {
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
