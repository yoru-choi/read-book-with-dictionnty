import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kGeminiKey = 'readbook_gemini_api_key';
const _kGithubPat = 'readbook_github_pat';

/// flutter_secure_storage-based sensitive data store (Android Keystore)
class SecureStorage {
  SecureStorage._();
  static final SecureStorage instance = SecureStorage._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<String?> getGeminiKey() => _storage.read(key: _kGeminiKey);
  Future<void> setGeminiKey(String key) => _storage.write(key: _kGeminiKey, value: key);

  Future<String?> getGithubPat() => _storage.read(key: _kGithubPat);
  Future<void> setGithubPat(String pat) => _storage.write(key: _kGithubPat, value: pat);

  Future<void> clearAll() async {
    await _storage.delete(key: _kGeminiKey);
    await _storage.delete(key: _kGithubPat);
  }
}
