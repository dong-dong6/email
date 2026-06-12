import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData light() => _theme(Brightness.light, const Color(0xFF25636F));
  static ThemeData dark() => _theme(Brightness.dark, const Color(0xFF7DD3C7));

  static ThemeData _theme(Brightness brightness, Color seed) {
    final scheme =
        ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        selectedLabelTextStyle:
            TextStyle(color: scheme.primary, fontWeight: FontWeight.w700),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withOpacity(0.45),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none),
      ),
    );
  }
}
