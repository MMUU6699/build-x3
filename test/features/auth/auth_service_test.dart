import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/auth/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('uses the canonical Supabase OAuth redirect URL', () {
    expect(AuthService.authRedirectUrl, 'buildx://login-callback');
  });

  group('AuthService.mapAuthError', () {
    test('maps invalid_credentials to user friendly message', () {
      const exception = AuthException('Invalid login credentials');
      expect(
        AuthService.mapAuthError(exception),
        'Incorrect email or password.',
      );
    });

    test('maps user_already_exists to email exists message', () {
      const exception = AuthException('User already registered');
      expect(
        AuthService.mapAuthError(exception),
        'An account with this email already exists.',
      );
    });

    test('maps weak_password to weak password message', () {
      const exception = AuthException(
        'weak_password: Password should be at least 6 characters',
      );
      expect(
        AuthService.mapAuthError(exception),
        'Password is too weak. Use at least 6 characters.',
      );
    });

    test('maps user cancelled to cancelled message', () {
      const exception = AuthException('user_cancelled');
      expect(AuthService.mapAuthError(exception), 'Sign in was cancelled.');
    });

    test('maps rate limit to try again later message', () {
      const exception = AuthException('over_request_rate_limit');
      expect(
        AuthService.mapAuthError(exception),
        'Too many attempts. Please try again later.',
      );
    });

    test('maps SocketException to network error message', () {
      const exception = SocketException('Failed host lookup');
      expect(
        AuthService.mapAuthError(exception),
        'Network error. Please check your connection and try again.',
      );
    });

    test('maps TimeoutException to timeout message', () {
      final exception = TimeoutException('Request timed out');
      expect(
        AuthService.mapAuthError(exception),
        'Connection timed out. Please try again.',
      );
    });

    test('maps generic exception cleanly', () {
      final exception = Exception('Custom server error');
      expect(AuthService.mapAuthError(exception), 'Custom server error');
    });
  });
}
