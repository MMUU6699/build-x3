import 'package:flutter/material.dart';
import 'package:Kelivo/features/auth/services/auth_service.dart';
import 'package:Kelivo/features/auth/widgets/auth_glass_button.dart';
import 'package:Kelivo/features/auth/widgets/auth_text_field.dart';
import 'package:Kelivo/features/auth/pages/login_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/theme/app_font_weights.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();

    final l10n = AppLocalizations.of(context);
    if (email.isEmpty) {
      setState(
        () => _error =
            l10n?.authErrorInvalidCredentials ?? 'Please enter your email',
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await AuthService.resetPassword(email);
      if (mounted) {
        setState(() {
          _sent = true;
        });
      }
    } catch (e) {
      setState(() {
        _error = AuthService.mapAuthError(e);
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(l10n?.authResetPassword ?? 'Reset password'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: _sent
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 48),
                          Icon(Lucide.Mail, size: 48, color: cs.primary),
                          const SizedBox(height: 24),
                          Text(
                            l10n?.authCheckYourEmail ?? 'Check your email',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: AppFontWeights.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n?.authResetLinkSent ??
                                'We sent a password reset link to ${_emailController.text.trim()}.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
                          AuthGlassButton(
                            variant: AuthGlassButtonVariant.primary,
                            label: l10n?.authBackToLogin ?? 'Back to login',
                            onTap: () {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (_) => const LoginPage(),
                                ),
                              );
                            },
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 24),
                          Text(
                            l10n?.authForgotPassword ??
                                "Enter your email address and we'll send you a link to reset your password.",
                          ),
                          const SizedBox(height: 24),
                          AuthTextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            hintText: l10n?.authEmail ?? 'Email',
                          ),
                          const SizedBox(height: 8),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                _error!,
                                style: TextStyle(color: cs.error, fontSize: 13),
                              ),
                            ),
                          const SizedBox(height: 24),
                          AuthGlassButton(
                            variant: AuthGlassButtonVariant.primary,
                            label: l10n?.authSendResetLink ?? 'Send reset link',
                            isLoading: _loading,
                            onTap: _resetPassword,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
