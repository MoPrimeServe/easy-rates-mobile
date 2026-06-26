// theme_controller.dart — the app-wide brightness switch.
//
// Holds the live [ThemeMode] and flips light↔dark. Mounted above MaterialApp
// (see main.dart) so any widget can read or toggle it via provider:
//   context.read<ThemeController>().toggle();   // flip
//   context.watch<ThemeController>().isDark;     // rebuild on change
import 'package:flutter/material.dart';

class ThemeController extends ChangeNotifier {
  ThemeController({ThemeMode initial = ThemeMode.system}) : _mode = initial;

  ThemeMode _mode;
  ThemeMode get mode => _mode;

  /// True once the user has explicitly chosen dark. While [_mode] is still
  /// [ThemeMode.system] this is false, so the first toggle lands on dark.
  bool get isDark => _mode == ThemeMode.dark;

  /// Flip between explicit light and dark, leaving `system` behind on first use.
  void toggle() => setMode(_mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);

  void setMode(ThemeMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
  }
}
