import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:turtle_base/core/theme/theme_preset.dart';

/// The user's chosen shadcn color scheme, stored per-device via
/// shared_preferences - same reasoning as ThemeController: a display
/// setting for this device, not domain content the user wants synced
/// across devices.
class ThemePresetController extends ChangeNotifier {
  ThemePresetController._(this._prefs, this._preset);

  static const _prefsKey = 'theme_preset';

  final SharedPreferences _prefs;
  ThemePreset _preset;

  ThemePreset get preset => _preset;

  /// Loads the stored preference, defaulting to [ThemePreset.green] (the
  /// app's original hardcoded theme) if none was ever set. Call once at
  /// app startup, before runApp().
  static Future<ThemePresetController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    final preset = ThemePreset.values.firstWhere(
      (p) => p.name == stored,
      orElse: () => ThemePreset.green,
    );
    return ThemePresetController._(prefs, preset);
  }

  Future<void> setPreset(ThemePreset preset) async {
    if (preset == _preset) return;
    _preset = preset;
    notifyListeners();
    await _prefs.setString(_prefsKey, preset.name);
  }
}
