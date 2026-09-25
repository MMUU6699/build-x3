import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:Kelivo/features/auth/pages/login_page.dart';
import 'package:Kelivo/features/auth/pages/signup_page.dart';
import 'package:Kelivo/features/auth/services/auth_service.dart';
import 'package:Kelivo/features/auth/widgets/auth_glass_button.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/snackbar.dart';
import 'package:Kelivo/theme/app_font_weights.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';

class AuthLandingPage extends StatefulWidget {
  const AuthLandingPage({super.key});

  @override
  State<AuthLandingPage> createState() => _AuthLandingPageState();
}

class _AuthLandingPageState extends State<AuthLandingPage> {
  bool _googleLoading = false;

  Future<void> _signInWithGoogle(BuildContext context) async {
    if (_googleLoading) return;
    setState(() => _googleLoading = true);
    try {
      final launched = await AuthService.signInWithGoogle();
      if (!launched && context.mounted) {
        showAppSnackBar(
          context,
          message: 'Could not open Google sign-in. Please try again.',
          type: NotificationType.error,
        );
      }
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: AuthService.mapAuthError(e),
          type: NotificationType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Spacer(flex: 3),
                Column(
                  children: [
                    Text(
                      'Build X',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: AppFontWeights.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Your AI workspace',
                      style: TextStyle(
                        fontSize: 15,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
                const Spacer(flex: 2),
                Padding(
                  padding: const EdgeInsets.only(
                    left: 24,
                    right: 24,
                    bottom: 32,
                  ),
                  child: Column(
                    children: [
                      AuthGlassButton(
                        variant: AuthGlassButtonVariant.primary,
                        label:
                            l10n?.authContinueWithGoogle ??
                            'Continue with Google',
                        leading: SvgPicture.asset(
                          'assets/icons/google-color.svg',
                          width: 20,
                          height: 20,
                        ),
                        isLoading: _googleLoading,
                        onTap: () => _signInWithGoogle(context),
                      ),
                      const SizedBox(height: 12),
                      AuthGlassButton(
                        variant: AuthGlassButtonVariant.outlined,
                        icon: Lucide.UserPlus,
                        label: l10n?.authSignUp ?? 'Sign up',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SignupPage(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      AuthGlassButton(
                        variant: AuthGlassButtonVariant.text,
                        icon: Lucide.LogIn,
                        label: l10n?.authLogIn ?? 'Log in',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const LoginPage(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
