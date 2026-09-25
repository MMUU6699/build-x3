import 'package:flutter/material.dart';
import 'package:Kelivo/core/services/haptics.dart';
import 'package:Kelivo/theme/app_font_weights.dart';

enum AuthGlassButtonVariant { primary, outlined, text }

class AuthGlassButton extends StatefulWidget {
  const AuthGlassButton({
    super.key,
    required this.onTap,
    required this.label,
    this.icon,
    this.leading,
    this.variant = AuthGlassButtonVariant.primary,
    this.isLoading = false,
    this.enabled = true,
  });

  final VoidCallback onTap;
  final String label;
  final IconData? icon;
  final Widget? leading;
  final AuthGlassButtonVariant variant;
  final bool isLoading;
  final bool enabled;

  @override
  State<AuthGlassButton> createState() => _AuthGlassButtonState();
}

class _AuthGlassButtonState extends State<AuthGlassButton> {
  bool _pressed = false;

  void _handleTapDown(TapDownDetails details) {
    if (widget.enabled && !widget.isLoading) {
      setState(() => _pressed = true);
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (widget.enabled && !widget.isLoading) {
      setState(() => _pressed = false);
    }
  }

  void _handleTapCancel() {
    if (_pressed) {
      setState(() => _pressed = false);
    }
  }

  void _handleTap() {
    if (widget.enabled && !widget.isLoading) {
      Haptics.light();
      widget.onTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isEnabled = widget.enabled && !widget.isLoading;

    Color backgroundColor;
    Color foregroundColor;
    Border? border;

    switch (widget.variant) {
      case AuthGlassButtonVariant.primary:
        backgroundColor = cs.primary;
        foregroundColor = cs.onPrimary;
        border = null;
        break;
      case AuthGlassButtonVariant.outlined:
        backgroundColor = Colors.transparent;
        foregroundColor = cs.onSurface;
        border = Border.all(
          color: cs.outline.withValues(alpha: 0.3),
          width: 1.2,
        );
        break;
      case AuthGlassButtonVariant.text:
        backgroundColor = Colors.transparent;
        foregroundColor = cs.onSurface;
        border = null;
        break;
    }

    Widget content = widget.isLoading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator.adaptive(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.leading != null) ...[
                widget.leading!,
                const SizedBox(width: 10),
              ] else if (widget.icon != null) ...[
                Icon(widget.icon, size: 20, color: foregroundColor),
                const SizedBox(width: 10),
              ],
              Text(
                widget.label,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: foregroundColor,
                  fontSize: 16,
                  fontWeight: AppFontWeights.medium,
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      label: widget.label,
      enabled: isEnabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        onTap: _handleTap,
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: Opacity(
            opacity: widget.enabled ? 1.0 : 0.5,
            child: Container(
              height: 56,
              width: double.infinity,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(28),
                border: border,
              ),
              alignment: Alignment.center,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
