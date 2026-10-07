import 'package:flutter/material.dart';

/// Brand colors taken from the Play Y logo (direction A).
class VyroColors {
  static const violetLight = Color(0xFFA66BFF);
  static const violetDeep = Color(0xFF5B7CFF);
  static const teal = Color(0xFF2BF0CF);
  static const tealDeep = Color(0xFF3BA8FF);
  static const ink = Color(0xFF0A0818);
  static const panel = Color(0xFF141033);
  static const panelBorder = Color(0xFF2A2556);
  static const mist = Color(0xFF9A94C4);
}

/// UIX-01: Midnight (dark), Daylight (light), AMOLED Black, follow system.
enum VyroThemeMode { system, midnight, daylight, amoled }

/// UIX-07: accent themes.
enum VyroAccent { aurora, sunset, forest, ocean }

extension VyroAccentInfo on VyroAccent {
  Color get seed => switch (this) {
        VyroAccent.aurora => const Color(0xFF8B5CFF),
        VyroAccent.sunset => const Color(0xFFFF6B4A),
        VyroAccent.forest => const Color(0xFF2DBE6C),
        VyroAccent.ocean => const Color(0xFF2D8CFF),
      };

  String get label => switch (this) {
        VyroAccent.aurora => 'Aurora',
        VyroAccent.sunset => 'Sunset',
        VyroAccent.forest => 'Forest',
        VyroAccent.ocean => 'Ocean',
      };
}

extension VyroThemeModeInfo on VyroThemeMode {
  String get label => switch (this) {
        VyroThemeMode.system => 'System',
        VyroThemeMode.midnight => 'Midnight',
        VyroThemeMode.daylight => 'Daylight',
        VyroThemeMode.amoled => 'AMOLED black',
      };
}

ThemeData buildVyroTheme({
  required Brightness brightness,
  required Color seed,
  bool amoled = false,
}) {
  final base = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  final scheme = brightness == Brightness.dark
      ? base.copyWith(surface: amoled ? Colors.black : VyroColors.ink)
      : base;
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
    ),
  );
}
