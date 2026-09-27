import 'dart:io' show Platform;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../database/business_migration_engine.dart';

/// Secrets used by Build X. They are excluded from normal settings backups.
abstract final class BuildXSecureStore {
  static const _storage = FlutterSecureStorage();
  static const _nvidiaKey = 'build_x_nvidia_api_key';
  static const _nvidiaNemotronKey = 'build_x_nvidia_nemotron_api_key';
  static const _nvidiaGlmKey = 'build_x_nvidia_glm_api_key';
  static const _mistralKey = 'build_x_mistral_api_key';
  static const _cerebrasKey = 'build_x_cerebras_api_key';
  static const _workBackendUrlKey = 'build_x_work_backend_url';
  static const _browserAccount = 'build_x_browser_account';

  /// Sanitizes an API key by stripping quotes, angle brackets, whitespace, and leading 'Bearer ' prefixes.
  static String sanitizeApiKey(String raw) {
    var key = raw.trim().replaceAll('\r', '').replaceAll('\n', '').trim();
    while ((key.startsWith('"') && key.endsWith('"') && key.length >= 2) ||
        (key.startsWith("'") && key.endsWith("'") && key.length >= 2)) {
      key = key.substring(1, key.length - 1).trim();
    }
    while (key.startsWith('<') && key.endsWith('>') && key.length >= 2) {
      key = key.substring(1, key.length - 1).trim();
    }
    while (key.toLowerCase().startsWith('bearer ')) {
      key = key.substring(7).trim();
    }
    while ((key.startsWith('"') && key.endsWith('"') && key.length >= 2) ||
        (key.startsWith("'") && key.endsWith("'") && key.length >= 2) ||
        (key.startsWith('<') && key.endsWith('>') && key.length >= 2)) {
      key = key.substring(1, key.length - 1).trim();
    }
    return key;
  }

  /// Whether a string is a valid NVIDIA API key.
  static bool isValidNvidiaKey(String key) {
    return key.startsWith('nvapi-') && key.length >= 20;
  }

  /// Reads a user-provided NVIDIA API key from secure storage, falling back to
  /// development-only OS environment variables.
  /// Supports separate secrets: NVIDIA_NEMOTRON_API_KEY and NVIDIA_GLM_API_KEY.
  static Future<String> readNvidiaKey({String? modelId}) async {
    final isGlm = modelId != null && modelId.contains('glm');
    final isNemotron = modelId != null && modelId.contains('nemotron');

    // 1. Model-specific OS environment variables
    try {
      if (isGlm) {
        final envGlm = Platform.environment['NVIDIA_GLM_API_KEY'];
        if (envGlm != null) {
          final s = sanitizeApiKey(envGlm);
          if (isValidNvidiaKey(s)) return s;
        }
      } else if (isNemotron) {
        final envNemotron = Platform.environment['NVIDIA_NEMOTRON_API_KEY'];
        if (envNemotron != null) {
          final s = sanitizeApiKey(envNemotron);
          if (isValidNvidiaKey(s)) return s;
        }
      }

      // Check both specific variables if modelId is not strictly matching
      final envNemotron = Platform.environment['NVIDIA_NEMOTRON_API_KEY'];
      if (envNemotron != null) {
        final s = sanitizeApiKey(envNemotron);
        if (isValidNvidiaKey(s) && !isGlm) return s;
      }
      final envGlm = Platform.environment['NVIDIA_GLM_API_KEY'];
      if (envGlm != null) {
        final s = sanitizeApiKey(envGlm);
        if (isValidNvidiaKey(s) && isGlm) return s;
      }

      final envNvidia = Platform.environment['NVIDIA_API_KEY'];
      if (envNvidia != null) {
        final sanitized = sanitizeApiKey(envNvidia);
        if (isValidNvidiaKey(sanitized)) return sanitized;
      }

      final envWork = Platform.environment['WORK_LLM_API_KEY'];
      if (envWork != null) {
        final sanitized = sanitizeApiKey(envWork);
        if (isValidNvidiaKey(sanitized)) return sanitized;
      }

      final envBuildX = Platform.environment['BUILD_X_API_KEY'];
      if (envBuildX != null) {
        final sanitized = sanitizeApiKey(envBuildX);
        if (isValidNvidiaKey(sanitized)) return sanitized;
      }
    } catch (_) {}

    // 2. Flutter Secure Storage (model-specific then general)
    try {
      if (isGlm) {
        final storedGlm = await _storage.read(key: _nvidiaGlmKey);
        if (storedGlm != null) {
          final s = sanitizeApiKey(storedGlm);
          if (isValidNvidiaKey(s)) return s;
        }
      } else if (isNemotron) {
        final storedNemotron = await _storage.read(key: _nvidiaNemotronKey);
        if (storedNemotron != null) {
          final s = sanitizeApiKey(storedNemotron);
          if (isValidNvidiaKey(s)) return s;
        }
      }

      final stored = await _storage.read(key: _nvidiaKey);
      if (stored != null) {
        final sanitized = sanitizeApiKey(stored);
        if (isValidNvidiaKey(sanitized)) return sanitized;
      }
    } catch (_) {}

    // Migrate the legacy plaintext preference once, then erase it.
    try {
      final prefKey = await BusinessMigrationEngine.takeLegacyStringPreference(
        _nvidiaKey,
      );
      if (prefKey != null) {
        final sanitized = sanitizeApiKey(prefKey);
        if (isValidNvidiaKey(sanitized)) {
          await _storage.write(key: _nvidiaKey, value: sanitized);
          return sanitized;
        }
      }
    } catch (_) {}

    // 3. Check legacy secure slots only if they hold an NVIDIA key.
    try {
      final legacyMistral = await _storage.read(key: _mistralKey);
      if (legacyMistral != null) {
        final sanitized = sanitizeApiKey(legacyMistral);
        if (isValidNvidiaKey(sanitized)) return sanitized;
      }

      final legacyCerebras = await _storage.read(key: _cerebrasKey);
      if (legacyCerebras != null) {
        final sanitized = sanitizeApiKey(legacyCerebras);
        if (isValidNvidiaKey(sanitized)) return sanitized;
      }
    } catch (_) {}

    return '';
  }

  static Future<String> readGlmKey() => readNvidiaKey(modelId: 'glm');
  static Future<String> readNemotronKey() => readNvidiaKey(modelId: 'nemotron');

  static Future<void> saveGlmKey(String value) async {
    final key = sanitizeApiKey(value);
    if (key.isNotEmpty && !isValidNvidiaKey(key)) {
      throw const FormatException('Invalid NVIDIA API key format.');
    }
    if (key.isEmpty) {
      await _storage.delete(key: _nvidiaGlmKey);
    } else {
      await _storage.write(key: _nvidiaGlmKey, value: key);
    }
  }

  static Future<void> saveNemotronKey(String value) async {
    final key = sanitizeApiKey(value);
    if (key.isNotEmpty && !isValidNvidiaKey(key)) {
      throw const FormatException('Invalid NVIDIA API key format.');
    }
    if (key.isEmpty) {
      await _storage.delete(key: _nvidiaNemotronKey);
    } else {
      await _storage.write(key: _nvidiaNemotronKey, value: key);
    }
  }

  static Future<void> saveNvidiaKey(String value) async {
    final key = sanitizeApiKey(value);
    if (key.isNotEmpty && !isValidNvidiaKey(key)) {
      throw const FormatException('Invalid NVIDIA API key format.');
    }
    try {
      if (key.isEmpty) {
        await _storage.delete(key: _nvidiaKey);
      } else {
        await _storage.write(key: _nvidiaKey, value: key);
      }
    } catch (_) {}

    // Ensure old plaintext copies cannot survive a save/delete operation.
    try {
      await BusinessMigrationEngine.removeLegacyPreference(_nvidiaKey);
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
      final stored =
          (await _storage.read(key: _workBackendUrlKey))?.trim() ?? '';
      if (stored.isNotEmpty) return stored;
    } catch (_) {}
    return '';
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

  static const _serperApiKey = 'build_x_serper_api_key';
  static const _defaultSerperApiKey =
      '079f6339ef7354c75af1dc14fc08fd0276ae884d';

  /// Reads Serper.dev API key from environment or secure storage, seeding
  /// the project key if not yet set.
  static Future<String> readSerperApiKey() async {
    try {
      final env = Platform.environment['SERPER_API_KEY']?.trim();
      if (env != null && env.isNotEmpty) {
        return sanitizeApiKey(env);
      }
    } catch (_) {}
    try {
      final stored = await _storage.read(key: _serperApiKey);
      if (stored != null && stored.trim().isNotEmpty) {
        return sanitizeApiKey(stored);
      }
    } catch (_) {}
    try {
      await _storage.write(key: _serperApiKey, value: _defaultSerperApiKey);
    } catch (_) {}
    return _defaultSerperApiKey;
  }

  /// Saves or clears the Serper.dev API key in secure storage.
  static Future<void> saveSerperApiKey(String value) async {
    final sanitized = sanitizeApiKey(value);
    try {
      if (sanitized.isEmpty) {
        await _storage.delete(key: _serperApiKey);
      } else {
        await _storage.write(key: _serperApiKey, value: sanitized);
      }
    } catch (_) {}
  }
}
