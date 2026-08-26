import 'package:flutter/material.dart';

/// Identidad visual de Comandia: terracota, la misma marca cálida del panel web.
const _terracota = Color(0xFFC2410C);

final comandiaTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: _terracota,
    primary: _terracota,
  ),
  scaffoldBackgroundColor: const Color(0xFFF7F5F3),
  appBarTheme: const AppBarTheme(centerTitle: false),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  ),
);
