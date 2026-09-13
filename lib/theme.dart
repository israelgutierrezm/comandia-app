import 'package:flutter/material.dart';

/// Paleta e identidad visual de Comandia. La app es **oscuro dominante**: las superficies van en azul
/// marino profundo y los brillantes del logo (teal, cian, menta) se reservan para acentos, estados y
/// detalle —tal como el acceso del panel web—. Es la misma marca, llevada a un tema oscuro.
///
/// Todo color de marca vive aquí (una sola fuente); los widgets leen los roles de `ColorScheme`, así
/// que recolorear el esquema recolorea la app entera.
class BrandColors {
  BrandColors._();

  static const teal = Color(0xFF21D0B2); // teal de marca — acento primario
  static const cyan = Color(0xFF1DCDFE); // cian de marca — acento secundario
  static const mint = Color(0xFF34F5C5); // menta de marca — acento terciario
  static const navy = Color(0xFF2F455C); // azul marino de marca — chrome (barra superior, barra de navegación)
  static const navyDeep = Color(0xFF0F1D28); // fondo más profundo — scaffold
  static const navySurface = Color(0xFF16242F); // superficie de tarjetas, un paso sobre el fondo
  static const navyRaised = Color(0xFF243A4D); // superficie elevada / contenedores
  static const onDark = Color(0xFFE6EEF4); // texto principal sobre oscuro
  static const onDarkMuted = Color(0xFFB4C8D6); // texto atenuado sobre oscuro
}

/// Esquema oscuro: los neutros (superficies) se derivan del azul marino de marca y los acentos
/// brillantes se colocan encima. Las superficies concretas se fijan a mano para controlar la
/// profundidad del oscuro; los `on*` de los acentos van muy oscuros porque los brillantes lo piden.
final _darkScheme = ColorScheme.fromSeed(
  seedColor: BrandColors.navy,
  brightness: Brightness.dark,
).copyWith(
  primary: BrandColors.teal,
  onPrimary: const Color(0xFF04231E),
  primaryContainer: const Color(0xFF0B8A99),
  onPrimaryContainer: const Color(0xFFCFFFF6),
  secondary: BrandColors.cyan,
  onSecondary: const Color(0xFF042430),
  tertiary: BrandColors.mint,
  onTertiary: const Color(0xFF04291F),
  surface: BrandColors.navySurface,
  onSurface: BrandColors.onDark,
  surfaceContainerHighest: BrandColors.navyRaised,
  onSurfaceVariant: BrandColors.onDarkMuted,
  outline: const Color(0xFF41576B),
  outlineVariant: const Color(0xFF2A3D4E),
);

final comandiaTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: _darkScheme,
  scaffoldBackgroundColor: BrandColors.navyDeep,
  appBarTheme: const AppBarTheme(
    centerTitle: false,
    backgroundColor: BrandColors.navy,
    foregroundColor: Colors.white,
    elevation: 0,
  ),
  // La barra inferior va en azul marino; la pestaña activa se marca con el teal de marca.
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: BrandColors.navy,
    indicatorColor: BrandColors.teal.withValues(alpha: 0.22),
    iconTheme: WidgetStateProperty.resolveWith(
      (states) => IconThemeData(
        color: states.contains(WidgetState.selected) ? BrandColors.teal : BrandColors.onDarkMuted,
      ),
    ),
    labelTextStyle: WidgetStateProperty.resolveWith(
      (states) => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: states.contains(WidgetState.selected) ? BrandColors.teal : BrandColors.onDarkMuted,
      ),
    ),
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
