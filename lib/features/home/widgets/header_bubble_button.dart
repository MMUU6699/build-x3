import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../core/services/haptics.dart';
import '../../../theme/header_tokens.dart';

class HeaderBubbleButton extends StatefulWidget {
  const HeaderBubbleButton({
    super.key,
    required this.child,
    this.onTap,
    this.tooltip,
    this.size = AppHeaderTokens.baseSize,
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
    final isDark = theme.brightness == Brightness.dark;
    final idleBg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white;
    final pressBg = isDark
        ? Colors.white.withValues(alpha: 0.16)
        : const Color(0xFFF4F4F5);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.06);

    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        Haptics.light();
        widget.onTap?.call();
      },
      child: Container(
        // Keep a minimum 44x44 tap target area for mobile accessibility
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        alignment: Alignment.center,
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: ClipOval(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _pressed ? pressBg : idleBg,
                  border: widget.isDashed
                      ? null
                      : Border.all(color: border, width: 0.8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
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
          ),
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
