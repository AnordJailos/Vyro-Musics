import 'package:flutter/material.dart';
import 'vyro_theme.dart';

/// Holds the user's theme choices. Persistence (so choices survive a restart)
/// is added together with account settings sync (AUTH-12).
class ThemeController extends ChangeNotifier {
  VyroThemeMode _mode = VyroThemeMode.midnight;
  VyroAccent _accent = VyroAccent.aurora;

  VyroThemeMode get mode => _mode;
  VyroAccent get accent => _accent;

  void setMode(VyroThemeMode value) {
    if (value == _mode) return;
    _mode = value;
    notifyListeners();
  }

  void setAccent(VyroAccent value) {
    if (value == _accent) return;
    _accent = value;
    notifyListeners();
  }

  ThemeMode get themeMode => switch (_mode) {
        VyroThemeMode.system => ThemeMode.system,
        VyroThemeMode.daylight => ThemeMode.light,
        VyroThemeMode.midnight || VyroThemeMode.amoled => ThemeMode.dark,
      };

  ThemeData get light =>
      buildVyroTheme(brightness: Brightness.light, seed: _accent.seed);

  ThemeData get dark => buildVyroTheme(
        brightness: Brightness.dark,
        seed: _accent.seed,
        amoled: _mode == VyroThemeMode.amoled,
      );
}
