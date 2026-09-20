import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secrets used by Build X. They are excluded from normal settings backups.
abstract final class BuildXSecureStore {
  static const _storage = FlutterSecureStorage();
  static const _mistralKey = 'build_x_mistral_api_key';
  static const _browserAccount = 'build_x_browser_account';

  static Future<String> readMistralKey() async =>
      (await _storage.read(key: _mistralKey))?.trim() ?? '';

  static Future<void> saveMistralKey(String value) async {
    final key = value.trim();
    if (key.isEmpty) {
      await _storage.delete(key: _mistralKey);
    } else {
      await _storage.write(key: _mistralKey, value: key);
    }
  }

  static Future<String> readBrowserAccount() async =>
      await _storage.read(key: _browserAccount) ?? '';

  static Future<void> saveBrowserAccount(String value) async {
    if (value.trim().isEmpty) {
      await _storage.delete(key: _browserAccount);
    } else {
      await _storage.write(key: _browserAccount, value: value.trim());
    }
  }
}
