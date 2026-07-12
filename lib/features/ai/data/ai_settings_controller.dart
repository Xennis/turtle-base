import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:turtle_base/features/ai/data/ai_provider.dart';

/// The user's chosen default AI model, stored per-device via
/// shared_preferences - same reasoning as ThemeController: a device-local
/// choice, not domain content that should be CRDT-synced.
class AiSettingsController extends ChangeNotifier {
  AiSettingsController._(this._prefs, this._model);

  static const _prefsKey = 'ai_default_model';

  final SharedPreferences _prefs;
  AiModel _model;

  AiModel get selectedModel => _model;

  /// Loads the stored preference, defaulting to the first [AiModel] if
  /// none was ever set. Call once at app startup, before runApp().
  static Future<AiSettingsController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    final model = AiModel.values.firstWhere((m) => m.name == stored, orElse: () => AiModel.values.first);
    return AiSettingsController._(prefs, model);
  }

  Future<void> setModel(AiModel model) async {
    if (model == _model) return;
    _model = model;
    notifyListeners();
    await _prefs.setString(_prefsKey, model.name);
  }
}
