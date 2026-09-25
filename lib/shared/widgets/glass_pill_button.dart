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
  });

  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final String? semanticLabel;

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
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor = isDark
        ? cs.surface.withValues(alpha: 0.12)
        : cs.surfaceContainerHighest.withValues(alpha: 0.85);

    final borderColor = cs.outline.withValues(alpha: isDark ? 0.15 : 0.12);
    final shadowColor = Colors.black.withValues(alpha: isDark ? 0.35 : 0.08);

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
                  filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
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
                          Icon(widget.icon, size: 18, color: cs.onSurface),
                          const SizedBox(width: 8),
                          Text(
                            widget.label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              fontWeight: AppFontWeights.medium,
                              color: cs.onSurface,
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
