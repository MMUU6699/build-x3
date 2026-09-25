import 'package:flutter/material.dart';
import 'package:Kelivo/features/auth/services/auth_service.dart';
import 'package:Kelivo/features/auth/widgets/auth_glass_button.dart';
import 'package:Kelivo/features/auth/widgets/auth_text_field.dart';
import 'package:Kelivo/features/auth/pages/login_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/theme/app_font_weights.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _displayNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;
  bool _emailConfirmationRequired = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    final displayName = _displayNameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    final l10n = AppLocalizations.of(context);
    if (displayName.isEmpty || email.isEmpty || password.isEmpty) {
      setState(
        () => _error = l10n?.authErrorGeneric ?? 'Please fill out all fields',
      );
      return;
    }
    if (password.length < 6) {
      setState(
        () => _error =
            l10n?.authErrorWeakPassword ??
            'Password must be at least 6 characters',
      );
      return;
    }
    if (password != confirmPassword) {
      setState(
        () => _error =
            l10n?.authErrorPasswordMismatch ?? 'Passwords do not match',
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await AuthService.signUp(email, password, displayName);
      if (response.session != null) {
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else if (response.user != null) {
        setState(() {
          _emailConfirmationRequired = true;
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

    if (_emailConfirmationRequired) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                      l10n?.authEmailConfirmationSent(
                            _emailController.text.trim(),
                          ) ??
                          'We sent a confirmation link to ${_emailController.text.trim()}. Please check your inbox.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    AuthGlassButton(
                      variant: AuthGlassButtonVariant.primary,
                      label: l10n?.authBackToLogin ?? 'Back to login',
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(l10n?.authCreateAccount ?? 'Create account'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    AuthTextField(
                      controller: _displayNameController,
                      hintText: l10n?.authDisplayName ?? 'Display name',
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      hintText: l10n?.authEmail ?? 'Email',
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      autofillHints: const [AutofillHints.newPassword],
                      hintText: l10n?.authPassword ?? 'Password',
                      onToggleObscure: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirm,
                      autofillHints: const [AutofillHints.newPassword],
                      hintText: l10n?.authConfirmPassword ?? 'Confirm password',
                      onToggleObscure: () {
                        setState(() {
                          _obscureConfirm = !_obscureConfirm;
                        });
                      },
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
                      label: l10n?.authCreateAccount ?? 'Create account',
                      isLoading: _loading,
                      onTap: _signUp,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          l10n?.authAlreadyHaveAccount ??
                              'Already have an account?',
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => const LoginPage(),
                              ),
                            );
                          },
                          child: Text(l10n?.authLogIn ?? 'Log in'),
                        ),
                      ],
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
