import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:Kelivo/core/services/haptics.dart';
import 'package:Kelivo/theme/app_font_weights.dart';

class GlassPillButton extends StatefulWidget {
  const GlassPillButton({
    super.key,
    required this.onTap,
    required this.icon,
    required this.label,
    this.semanticLabel,
    this.primary = false,
  });

  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final String? semanticLabel;
  final bool primary;

  @override
  State<GlassPillButton> createState() => _GlassPillButtonState();
}

class _GlassPillButtonState extends State<GlassPillButton> {
  bool _pressed = false;

  void _handleTapDown(TapDownDetails details) =>
      setState(() => _pressed = true);
  void _handleTapUp(TapUpDetails details) => setState(() => _pressed = false);
  void _handleTapCancel() => setState(() => _pressed = false);

  void _handleTap() {
    Haptics.light();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : (_pressed ? const Color(0xFFF4F4F5) : Colors.white);

    final foregroundColor = isDark ? Colors.white : const Color(0xFF18181B);

    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.06);

    final shadowColor = Colors.black.withValues(alpha: isDark ? 0.25 : 0.10);

    return Semantics(
      button: true,
      label: widget.semanticLabel ?? widget.label,
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
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(23),
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: RepaintBoundary(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(23),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(23),
                      border: Border.all(color: borderColor, width: 0.8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(widget.icon, size: 18, color: foregroundColor),
                          const SizedBox(width: 8),
                          Text(
                            widget.label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              fontWeight: AppFontWeights.medium,
                              color: foregroundColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
