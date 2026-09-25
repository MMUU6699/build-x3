import 'package:flutter/material.dart';
import '../../../core/services/work/work_agent_event.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';

/// Minimal single-line Thinking state matching Manus parity.
/// Shows a clean plain line: "Build X is thinking…" with an optional collapsed affordance.
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
  bool _expanded = false;
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
    final hasReasoningContent = widget.thinkingEvent.content.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Single plain line: "Build X is thinking…" (Manus parity)
          Row(
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
                    ? 'Build X is thinking…'
                    : 'Thought for ${widget.thinkingEvent.elapsedSeconds}s',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: AppFontWeights.regular,
                  color: cs.onSurface.withValues(alpha: isDark ? 0.65 : 0.55),
                ),
              ),
              if (hasReasoningContent) ...[
                const SizedBox(width: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _expanded ? 'hide' : 'view reasoning',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.40),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          _expanded ? Lucide.ChevronUp : Lucide.ChevronDown,
                          size: 11,
                          color: cs.onSurface.withValues(alpha: 0.40),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          // Collapsed-by-default reasoning stream (only if user explicitly opens it)
          if (_expanded && hasReasoningContent)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.30),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  widget.thinkingEvent.content,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.45,
                    color: cs.onSurface.withValues(alpha: 0.75),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
