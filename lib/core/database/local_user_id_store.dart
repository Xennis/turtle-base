import 'package:shared_preferences/shared_preferences.dart';

/// Where an [AppDatabase] persists which `users` row this device considers
/// "itself" - device-local state, not synced (same idea as ThemeController
/// for theme mode). Abstracted (rather than [AppDatabase] talking to
/// `shared_preferences` directly) so simulating multiple "devices" in one
/// process - as the sync tests do, each with its own [AppDatabase]
/// instance - doesn't have every instance reading/writing the same global
/// mock storage; passing none just makes `currentUserId()` cache its
/// resolution in memory instead of persisting it.
abstract class LocalUserIdStore {
  String? get();

  Future<void> set(String userId);
}

class SharedPreferencesLocalUserIdStore implements LocalUserIdStore {
  SharedPreferencesLocalUserIdStore(this._prefs);

  static const _prefsKey = 'local_user_id';

  final SharedPreferences _prefs;

  static Future<SharedPreferencesLocalUserIdStore> load() async {
    return SharedPreferencesLocalUserIdStore(await SharedPreferences.getInstance());
  }

  @override
  String? get() => _prefs.getString(_prefsKey);

  @override
  Future<void> set(String userId) => _prefs.setString(_prefsKey, userId);
}
