import 'package:flutter/material.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/theme/app_font_weights.dart';

class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    this.label,
    this.hintText,
    this.errorText,
    this.obscureText = false,
    this.onToggleObscure,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.autofillHints,
    this.enabled = true,
    this.focusNode,
  });

  final TextEditingController controller;
  final String? label;
  final String? hintText;
  final String? errorText;
  final bool obscureText;
  final VoidCallback? onToggleObscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.25)),
    );

    final errorBorder = border.copyWith(
      borderSide: BorderSide(color: cs.error),
    );

    final focusedBorder = border.copyWith(
      borderSide: BorderSide(color: cs.primary, width: 2),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              fontWeight: AppFontWeights.medium,
              color: enabled
                  ? cs.onSurface
                  : cs.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          autofillHints: autofillHints,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: enabled ? cs.onSurface : cs.onSurface.withValues(alpha: 0.5),
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: theme.textTheme.bodyLarge?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            filled: true,
            fillColor: cs.surfaceContainerLow.withValues(alpha: 0.5),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: border,
            enabledBorder: border,
            focusedBorder: focusedBorder,
            errorBorder: errorBorder,
            focusedErrorBorder: errorBorder,
            suffixIcon: onToggleObscure != null
                ? IconButton(
                    icon: Icon(
                      obscureText ? Lucide.Eye : Lucide.EyeOff,
                      color: cs.onSurfaceVariant,
                    ),
                    onPressed: onToggleObscure,
                    tooltip: obscureText ? 'Show password' : 'Hide password',
                  )
                : null,
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 4),
          Text(
            errorText!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.error,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}
