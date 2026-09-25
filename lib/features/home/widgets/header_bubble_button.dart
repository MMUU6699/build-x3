import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/services/haptics.dart';

/// Clean circular bubble button for header actions in Build X.
///
/// Designed with standard 44x44 touch-target dimensions, subtle border,
/// soft drop shadow, and tactile feedback. Supports a dashed border variant
/// for temporary/incognito mode.
class HeaderBubbleButton extends StatefulWidget {
  const HeaderBubbleButton({
    super.key,
    required this.child,
    this.onTap,
    this.tooltip,
    this.size = 44.0,
    this.isDashed = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final bool isDashed;

  @override
  State<HeaderBubbleButton> createState() => _HeaderBubbleButtonState();
}

class _HeaderBubbleButtonState extends State<HeaderBubbleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bg = isDark
        ? cs.surface.withValues(alpha: 0.90)
        : cs.surface.withValues(alpha: 0.98);
    final border = isDark
        ? cs.outline.withValues(alpha: 0.30)
        : cs.outline.withValues(alpha: 0.20);

    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        Haptics.light();
        widget.onTap?.call();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bg,
            border: widget.isDashed
                ? null
                : Border.all(color: border, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: widget.isDashed
              ? CustomPaint(
                  foregroundPainter: _DashedCirclePainter(
                    color: border,
                    strokeWidth: 1.2,
                    dashLength: 4.5,
                    gapLength: 3.5,
                  ),
                  child: Center(child: widget.child),
                )
              : Center(child: widget.child),
        ),
      ),
    );

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      return Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter({
    required this.color,
    this.strokeWidth = 1.2,
    this.dashLength = 4.5,
    this.gapLength = 3.5,
  });

  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final radius = (size.width - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final circumference = 2 * math.pi * radius;
    final totalDashCount = (circumference / (dashLength + gapLength)).floor();
    if (totalDashCount <= 0) return;

    final adjustedSweep = (2 * math.pi) / totalDashCount;
    final dashSweep = adjustedSweep * (dashLength / (dashLength + gapLength));

    for (int i = 0; i < totalDashCount; i++) {
      final startAngle = i * adjustedSweep;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        dashSweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) =>
      color != oldDelegate.color ||
      strokeWidth != oldDelegate.strokeWidth ||
      dashLength != oldDelegate.dashLength ||
      gapLength != oldDelegate.gapLength;
}
