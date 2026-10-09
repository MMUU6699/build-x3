import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/features/auth/providers/auth_provider.dart';
import 'package:Kelivo/features/auth/pages/auth_landing_page.dart';
import 'package:Kelivo/features/auth/pages/update_password_page.dart';

/// A widget that gates content based on authentication status.
class AuthGate extends StatelessWidget {
  /// The widget to show when the user is authenticated.
  final Widget authenticatedChild;

  const AuthGate({super.key, required this.authenticatedChild});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    switch (authProvider.status) {
      case AuthStatus.unknown:
        return const Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Build X',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 24),
                CircularProgressIndicator.adaptive(),
              ],
            ),
          ),
        );
      case AuthStatus.unconfigured:
      case AuthStatus.configurationError:
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Authentication unavailable',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        authProvider.configurationError ??
                            'Supabase authentication is not configured.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      case AuthStatus.unauthenticated:
        return const AuthLandingPage();
      case AuthStatus.passwordRecovery:
        return const UpdatePasswordPage();
      case AuthStatus.authenticated:
        return authenticatedChild;
    }
  }
}
