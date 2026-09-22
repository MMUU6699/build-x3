import 'dart:io' show Platform;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Secrets used by Build X. They are excluded from normal settings backups.
abstract final class BuildXSecureStore {
  static const _storage = FlutterSecureStorage();
  static const _nvidiaKey = 'build_x_nvidia_api_key';
  static const _mistralKey = 'build_x_mistral_api_key';
  static const _cerebrasKey = 'build_x_cerebras_api_key';
  static const _workBackendUrlKey = 'build_x_work_backend_url';
  static const _browserAccount = 'build_x_browser_account';

  /// Sanitizes an API key by stripping quotes, whitespace, and leading 'Bearer ' prefixes.
  static String sanitizeApiKey(String raw) {
    var key = raw.trim();
    if (key.startsWith('"') && key.endsWith('"') && key.length >= 2) {
      key = key.substring(1, key.length - 1).trim();
    } else if (key.startsWith("'") && key.endsWith("'") && key.length >= 2) {
      key = key.substring(1, key.length - 1).trim();
    }
    if (key.toLowerCase().startsWith('bearer ')) {
      key = key.substring(7).trim();
    }
    return key;
  }

  /// Reads NVIDIA API key from secure storage, falling back to environment variables
  /// (NVIDIA_API_KEY, WORK_LLM_API_KEY, BUILD_X_API_KEY) and SharedPreferences.
  /// Never returns a legacy Mistral (mk-...) or Cerebras (csk-...) key.
  static Future<String> readNvidiaKey() async {
    try {
      final envNvidia = Platform.environment['NVIDIA_API_KEY'];
      if (envNvidia != null) {
        final sanitized = sanitizeApiKey(envNvidia);
        if (sanitized.isNotEmpty) return sanitized;
      }

      final envWork = Platform.environment['WORK_LLM_API_KEY'];
      if (envWork != null) {
        final sanitized = sanitizeApiKey(envWork);
        if (sanitized.isNotEmpty) return sanitized;
      }

      final envBuildX = Platform.environment['BUILD_X_API_KEY'];
      if (envBuildX != null) {
        final sanitized = sanitizeApiKey(envBuildX);
        if (sanitized.isNotEmpty) return sanitized;
      }
    } catch (_) {}

    try {
      final stored = await _storage.read(key: _nvidiaKey);
      if (stored != null) {
        final sanitized = sanitizeApiKey(stored);
        if (sanitized.isNotEmpty) return sanitized;
      }
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      final prefKey = prefs.getString(_nvidiaKey);
      if (prefKey != null) {
        final sanitized = sanitizeApiKey(prefKey);
        if (sanitized.isNotEmpty) return sanitized;
      }
    } catch (_) {}

    // Check legacy slots ONLY if they actually hold an NVIDIA key (nvapi-...)
    try {
      final legacyMistral = await _storage.read(key: _mistralKey);
      if (legacyMistral != null) {
        final sanitized = sanitizeApiKey(legacyMistral);
        if (sanitized.startsWith('nvapi-')) return sanitized;
      }

      final legacyCerebras = await _storage.read(key: _cerebrasKey);
      if (legacyCerebras != null) {
        final sanitized = sanitizeApiKey(legacyCerebras);
        if (sanitized.startsWith('nvapi-')) return sanitized;
      }
    } catch (_) {}

    return '';
  }

  static Future<void> saveNvidiaKey(String value) async {
    final key = sanitizeApiKey(value);
    try {
      if (key.isEmpty) {
        await _storage.delete(key: _nvidiaKey);
      } else {
        await _storage.write(key: _nvidiaKey, value: key);
      }
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      if (key.isEmpty) {
        await prefs.remove(_nvidiaKey);
      } else {
        await prefs.setString(_nvidiaKey, key);
      }
    } catch (_) {}
  }

  // Backwards compatibility accessors
  static Future<String> readMistralKey() => readNvidiaKey();
  static Future<void> saveMistralKey(String value) => saveNvidiaKey(value);

  static Future<String> readCerebrasKey() => readNvidiaKey();
  static Future<void> saveCerebrasKey(String value) => saveNvidiaKey(value);

  /// Reads the backend URL for the OpenHands server (if running remote VM or local).
  static Future<String> readWorkBackendUrl() async {
    try {
      final env = Platform.environment['OPENHANDS_BACKEND_URL']?.trim();
      if (env != null && env.isNotEmpty) return env;
    } catch (_) {}
    try {
      final stored = (await _storage.read(key: _workBackendUrlKey))?.trim() ?? '';
      if (stored.isNotEmpty) return stored;
    } catch (_) {}
    return 'http://localhost:8000';
  }

  static Future<void> saveWorkBackendUrl(String value) async {
    final url = value.trim();
    try {
      if (url.isEmpty) {
        await _storage.delete(key: _workBackendUrlKey);
      } else {
        await _storage.write(key: _workBackendUrlKey, value: url);
      }
    } catch (_) {}
  }

  static Future<String> readBrowserAccount() async {
    try {
      return await _storage.read(key: _browserAccount) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> saveBrowserAccount(String value) async {
    try {
      if (value.trim().isEmpty) {
        await _storage.delete(key: _browserAccount);
      } else {
        await _storage.write(key: _browserAccount, value: value.trim());
      }
    } catch (_) {}
  }
}
