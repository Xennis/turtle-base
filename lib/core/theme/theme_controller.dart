import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user's chosen theme (System/Light/Dark), stored per-device via
/// shared_preferences rather than in the (CRDT-synced) database - it's
/// a display setting for this device, not domain content the user
/// wants synced across devices.
class ThemeController extends ChangeNotifier {
  ThemeController._(this._prefs, this._mode);

  static const _prefsKey = 'theme_mode';

  final SharedPreferences _prefs;
  ThemeMode _mode;

  ThemeMode get mode => _mode;

  /// Loads the stored preference, defaulting to [ThemeMode.system] if
  /// none was ever set. Call once at app startup, before runApp(), so
  /// the correct theme is already known for the first frame.
  static Future<ThemeController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    final mode = ThemeMode.values.firstWhere(
      (m) => m.name == stored,
      orElse: () => ThemeMode.system,
    );
    return ThemeController._(prefs, mode);
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    await _prefs.setString(_prefsKey, mode.name);
  }
}
