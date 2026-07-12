import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:turtle_base/features/ai/data/ai_provider.dart';

/// Stores per-provider API keys in the platform's secure storage
/// (Keychain/Keystore/libsecret) - deliberately outside Drift/AppDatabase,
/// since anything in a synced table would leak into the CRDT changeset
/// files uploaded to Google Drive (see AI_INTEGRATION.md). Keys therefore
/// stay purely local to this device.
class AiKeyStorage {
  AiKeyStorage([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _keyFor(AiProvider provider) => 'ai_api_key_${provider.name}';

  Future<String?> read(AiProvider provider) => _storage.read(key: _keyFor(provider));

  Future<void> write(AiProvider provider, String apiKey) => _storage.write(key: _keyFor(provider), value: apiKey);

  Future<void> delete(AiProvider provider) => _storage.delete(key: _keyFor(provider));
}
