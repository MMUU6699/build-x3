import 'dart:io' show Platform, exit;

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:restart_app/restart_app.dart';

abstract final class PlatformUtils {
  PlatformUtils._();

  static bool get isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  static bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static bool get isDesktopTarget =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  static bool get isMobileTarget =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  static bool get isMacOS => !kIsWeb && Platform.isMacOS;

  static bool get isWindows => !kIsWeb && Platform.isWindows;

  static bool get isLinux => !kIsWeb && Platform.isLinux;

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  static bool get isIOS => !kIsWeb && Platform.isIOS;

  static Future<void> restartApp() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform == TargetPlatform.android || isDesktopTarget) {
      final result = await Restart.restartApp(mode: RestartMode.process);
      if (!result.success) {
        throw StateError('restart_app:${result.code ?? 'unknown'}');
      }
    } else {
      exit(0);
    }
  }
}
