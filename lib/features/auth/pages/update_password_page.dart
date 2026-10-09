import 'package:flutter/material.dart';
import 'package:Kelivo/features/auth/services/auth_service.dart';
import 'package:Kelivo/features/auth/widgets/auth_glass_button.dart';
import 'package:Kelivo/features/auth/widgets/auth_text_field.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

/// Completes a Supabase password-recovery session opened through the app link.
class UpdatePasswordPage extends StatefulWidget {
  const UpdatePasswordPage({super.key});

  @override
  State<UpdatePasswordPage> createState() => _UpdatePasswordPageState();
}

class _UpdatePasswordPageState extends State<UpdatePasswordPage> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    final l10n = AppLocalizations.of(context);
    final password = _passwordController.text;
    final confirmation = _confirmPasswordController.text;
    if (password.length < 6) {
      setState(() {
        _error =
            l10n?.authErrorWeakPassword ??
            'Password is too weak. Use at least 6 characters.';
      });
      return;
    }
    if (password != confirmation) {
      setState(() {
        _error = l10n?.authErrorPasswordMismatch ?? 'Passwords do not match.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.updatePassword(password);
      // Supabase emits userUpdated; AuthProvider then replaces this page with
      // the authenticated application through AuthGate.
    } catch (error) {
      if (mounted) {
        setState(() => _error = AuthService.mapAuthError(error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(l10n?.authResetPassword ?? 'Reset password')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    AuthTextField(
                      controller: _passwordController,
                      hintText: l10n?.authPassword ?? 'Password',
                      obscureText: _obscurePassword,
                      autofillHints: const [AutofillHints.newPassword],
                      onToggleObscure: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      controller: _confirmPasswordController,
                      hintText: l10n?.authConfirmPassword ?? 'Confirm password',
                      obscureText: _obscureConfirm,
                      autofillHints: const [AutofillHints.newPassword],
                      onToggleObscure: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          _error!,
                          style: TextStyle(color: cs.error, fontSize: 13),
                        ),
                      ),
                    const SizedBox(height: 24),
                    AuthGlassButton(
                      variant: AuthGlassButtonVariant.primary,
                      label: l10n?.authResetPassword ?? 'Update password',
                      isLoading: _loading,
                      onTap: _updatePassword,
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
