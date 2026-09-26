import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Kelivo/core/providers/user_provider.dart';

/// The authentication status of the application.
enum AuthStatus {
  unknown,
  unconfigured,
  configurationError,
  unauthenticated,
  passwordRecovery,
  authenticated,
}

/// A provider that manages the authentication state of the application.
class AuthProvider extends ChangeNotifier {
  final UserProvider? userProvider;
  AuthStatus _status = AuthStatus.unknown;
  User? _user;
  Session? _session;
  StreamSubscription<AuthState>? _subscription;
  bool _initialized = false;
  String? _configurationError;

  AuthProvider({this.userProvider}) {
    _init();
  }

  /// The current authentication status.
  AuthStatus get status => _status;

  /// Whether auth has completed initial evaluation.
  bool get isInitialized => _initialized;

  /// A diagnostic suitable for the configuration screen.
  String? get configurationError => _configurationError;

  @visibleForTesting
  void setStatusForTesting(AuthStatus status) {
    _status = status;
    notifyListeners();
  }

  /// The current authenticated user.
  User? get user => _user;

  /// The current authentication session.
  Session? get session => _session;

  void _syncProfile(User? user) {
    if (user == null || userProvider == null) return;
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final name =
        (metadata['display_name'] ?? metadata['full_name'] ?? metadata['name'])
            ?.toString();
    final avatar = (metadata['avatar_url'] ?? metadata['picture'])?.toString();
    userProvider!.syncFromAuthUser(
      authUserId: user.id,
      authDisplayName: name,
      authAvatarUrl: avatar,
      authEmail: user.email,
    );
  }

  void _init() {
    const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
    const rawPublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
    const rawAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    final supabasePublishableKey =
        rawPublishableKey.isNotEmpty ? rawPublishableKey : rawAnonKey;
    if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
      _status = AuthStatus.unconfigured;
      _configurationError =
          'SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY must be provided with '
          '--dart-define.';
      _initialized = true;
      notifyListeners();
      return;
    }

    try {
      final auth = Supabase.instance.client.auth;

      // Initial state setup
      _session = auth.currentSession;
      _user = auth.currentUser;
      _status = _session != null
          ? AuthStatus.authenticated
          : AuthStatus.unauthenticated;
      _initialized = true;
      if (_session != null) {
        _syncProfile(_user);
      }
      notifyListeners();

      // Listen to auth state changes
      _subscription = auth.onAuthStateChange.listen((data) {
        final AuthChangeEvent event = data.event;
        _session = data.session;
        _user = data.session?.user;

        if (event == AuthChangeEvent.passwordRecovery && _session != null) {
          _status = AuthStatus.passwordRecovery;
          _syncProfile(_user);
        } else if (event == AuthChangeEvent.signedIn ||
            event == AuthChangeEvent.tokenRefreshed ||
            event == AuthChangeEvent.userUpdated ||
            (event == AuthChangeEvent.initialSession && _session != null)) {
          _status = AuthStatus.authenticated;
          _syncProfile(_user);
        } else if (event == AuthChangeEvent.signedOut ||
            (event == AuthChangeEvent.initialSession && _session == null)) {
          _status = AuthStatus.unauthenticated;
          userProvider?.clearAuthUser();
        }

        _initialized = true;
        notifyListeners();
      });
    } catch (_) {
      _status = AuthStatus.configurationError;
      _configurationError =
          'Supabase authentication could not be initialized. Check the '
          'compile-time configuration and restart the app.';
      _initialized = true;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
