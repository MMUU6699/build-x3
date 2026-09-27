import 'package:flutter/material.dart';
import '../../../core/services/work/work_agent_event.dart';
import '../../../theme/app_font_weights.dart';

/// Minimal single-line Thinking state matching Manus parity.
/// Shows a clean plain line: "Thinking…" when streaming, or "Thought for Xs" when done.
/// Raw chain-of-thought is never exposed to the user.
class WorkThinkingCard extends StatefulWidget {
  const WorkThinkingCard({
    super.key,
    required this.thinkingEvent,
    this.isStreaming = false,
  });

  final WorkThinkingEvent thinkingEvent;
  final bool isStreaming;

  @override
  State<WorkThinkingCard> createState() => _WorkThinkingCardState();
}

class _WorkThinkingCardState extends State<WorkThinkingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.isStreaming)
            FadeTransition(
              opacity: Tween<double>(
                begin: 0.35,
                end: 1.0,
              ).animate(_pulseController),
              child: Container(
                width: 7,
                height: 7,
                margin: const EdgeInsetsDirectional.only(end: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
          Text(
            widget.isStreaming
                ? 'Thinking…'
                : 'Thought for ${widget.thinkingEvent.elapsedSeconds}s',
            style: TextStyle(
              fontSize: 14,
              fontWeight: AppFontWeights.regular,
              color: cs.onSurface.withValues(alpha: isDark ? 0.65 : 0.55),
            ),
          ),
        ],
      ),
    );
  }
}
