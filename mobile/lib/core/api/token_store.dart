import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists tokens in the platform keystore (Android Keystore / iOS Keychain).
/// Tokens are never written to shared preferences, files or logs.
abstract class TokenStore {
  Future<({String access, String refresh})?> read();
  Future<void> write({required String access, required String refresh});
  Future<void> clear();
  Future<String?> readValue(String key);
  Future<void> writeValue(String key, String? value);
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _accessKey = 'bizflow.access';
  static const _refreshKey = 'bizflow.refresh';

  @override
  Future<({String access, String refresh})?> read() async {
    final access = await _storage.read(key: _accessKey);
    final refresh = await _storage.read(key: _refreshKey);
    if (access == null || refresh == null) return null;
    return (access: access, refresh: refresh);
  }

  @override
  Future<void> write({required String access, required String refresh}) async {
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }

  @override
  Future<String?> readValue(String key) => _storage.read(key: 'bizflow.$key');

  @override
  Future<void> writeValue(String key, String? value) =>
      value == null ? _storage.delete(key: 'bizflow.$key') : _storage.write(key: 'bizflow.$key', value: value);
}

/// In-memory store for tests.
class MemoryTokenStore implements TokenStore {
  ({String access, String refresh})? _tokens;
  final Map<String, String> _values = {};

  @override
  Future<({String access, String refresh})?> read() async => _tokens;

  @override
  Future<void> write({required String access, required String refresh}) async =>
      _tokens = (access: access, refresh: refresh);

  @override
  Future<void> clear() async => _tokens = null;

  @override
  Future<String?> readValue(String key) async => _values[key];

  @override
  Future<void> writeValue(String key, String? value) async =>
      value == null ? _values.remove(key) : _values[key] = value;
}
