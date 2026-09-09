import 'package:flutter/material.dart';

/// Identidad visual de Comandia: el logo es una C en degradado cian→teal→menta sobre azul marino
/// (#2F455C), la misma marca del panel web. El acento funcional es un teal PROFUNDO, legible con texto
/// blanco —el cian/teal brillantes del logo no lo son—; el chrome (barra superior) va en azul marino.
const _teal = Color(0xFF21D0B2); // teal de marca (semilla del esquema)
const _acento = Color(0xFF0B8A99); // teal profundo: primary legible con texto blanco
const _marino = Color(0xFF2F455C); // azul marino de marca: chrome

final comandiaTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: _teal,
    primary: _acento,
    onPrimary: Colors.white,
  ),
  scaffoldBackgroundColor: const Color(0xFFF1F5F8),
  appBarTheme: const AppBarTheme(
    centerTitle: false,
    backgroundColor: _marino,
    foregroundColor: Colors.white,
    elevation: 0,
  ),
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
