import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// A service class that wraps Supabase authentication methods.
class AuthService {
  /// Private constructor to prevent instantiation.
  AuthService._();

  static GoTrueClient get _auth => Supabase.instance.client.auth;

  static const authRedirectUrl = 'buildx://login-callback';

  /// Whether Supabase is initialized and configured.
  static bool get isConfigured {
    try {
      final url = Supabase.instance.client.rest.url;
      return url.isNotEmpty &&
          !url.contains('placeholder') &&
          url != 'https://xyzcompany.supabase.co';
    } catch (_) {
      return false;
    }
  }

  /// Returns the currently signed-in user, or null if unauthenticated.
  static User? get currentUser {
    try {
      return _auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  /// A stream of authentication state changes.
  static Stream<AuthState> get authStateChanges {
    try {
      return _auth.onAuthStateChange;
    } catch (_) {
      return const Stream<AuthState>.empty();
    }
  }

  /// Signs in a user with Google OAuth.
  static Future<bool> signInWithGoogle() async {
    try {
      return await _auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: authRedirectUrl,
      );
    } catch (e) {
      throw Exception(mapAuthError(e));
    }
  }

  /// Signs in a user with an email and password.
  static Future<AuthResponse> signInWithPassword(
    String email,
    String password,
  ) async {
    try {
      return await _auth.signInWithPassword(email: email, password: password);
    } catch (e) {
      throw Exception(mapAuthError(e));
    }
  }

  /// Signs up a new user with an email, password, and display name.
  static Future<AuthResponse> signUp(
    String email,
    String password,
    String displayName,
  ) async {
    try {
      return await _auth.signUp(
        email: email,
        password: password,
        data: {'display_name': displayName},
      );
    } catch (e) {
      throw Exception(mapAuthError(e));
    }
  }

  /// Sends a password reset email to the given address.
  static Future<void> resetPassword(String email) async {
    try {
      await _auth.resetPasswordForEmail(email, redirectTo: authRedirectUrl);
    } catch (e) {
      throw Exception(mapAuthError(e));
    }
  }

  /// Updates the password for the authenticated password-recovery session.
  static Future<UserResponse> updatePassword(String password) async {
    try {
      return await _auth.updateUser(UserAttributes(password: password));
    } catch (e) {
      throw Exception(mapAuthError(e));
    }
  }

  /// Signs out the current user.
  static Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      throw Exception(mapAuthError(e));
    }
  }

  /// Maps an authentication error to a user-friendly English string.
  static String mapAuthError(Object error) {
    if (error is AuthException) {
      final code = error.message.toLowerCase();
      if (code.contains('cancel') || code.contains('user_cancelled')) {
        return 'Sign in was cancelled.';
      } else if (code.contains('invalid_credentials') ||
          code.contains('invalid_grant') ||
          code.contains('invalid login credentials')) {
        return 'Incorrect email or password.';
      } else if (code.contains('user_already_exists') ||
          code.contains('email_exists') ||
          code.contains('already registered')) {
        return 'An account with this email already exists.';
      } else if (code.contains('weak_password')) {
        return 'Password is too weak. Use at least 6 characters.';
      } else if (code.contains('email_not_confirmed')) {
        return 'Please verify your email address first.';
      } else if (code.contains('too_many_requests') ||
          code.contains('over_request_rate_limit') ||
          code.contains('rate limit')) {
        return 'Too many attempts. Please try again later.';
      }
      return error.message.isNotEmpty
          ? error.message
          : 'Something went wrong. Please try again.';
    } else if (error is SocketException ||
        error.toString().toLowerCase().contains('socketexception') ||
        error.toString().toLowerCase().contains('network')) {
      return 'Network error. Please check your connection and try again.';
    } else if (error is TimeoutException ||
        error.toString().toLowerCase().contains('timeout')) {
      return 'Connection timed out. Please try again.';
    }

    final msg = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    return msg.isNotEmpty ? msg : 'Something went wrong. Please try again.';
  }
}
