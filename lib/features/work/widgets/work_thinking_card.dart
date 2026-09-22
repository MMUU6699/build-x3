import 'package:flutter/material.dart';
import '../../../core/services/work/work_agent_event.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';

/// 2. Thinking State Card: Collapsible reasoning trace block matching Claude/ChatGPT extended thinking.
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

class _WorkThinkingCardState extends State<WorkThinkingCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final seconds = widget.thinkingEvent.elapsedSeconds;
    final effort = widget.thinkingEvent.effort;
    final label = widget.isStreaming
        ? 'Thinking ($effort effort, ${seconds}s)...'
        : 'Thought for ${seconds}s ($effort effort)';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest.withAlpha(200),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cs.outline.withAlpha(40),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Lucide.Brain,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      fontSize: 13,
                      fontWeight: AppFontWeights.medium,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (widget.isStreaming) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation<Color>(cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    _expanded ? Lucide.ChevronUp : Lucide.ChevronDown,
                    size: 15,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: cs.outline.withAlpha(25)),
            Container(
              padding: const EdgeInsets.all(14),
              constraints: const BoxConstraints(maxHeight: 280),
              child: SingleChildScrollView(
                child: SelectableText(
                  widget.thinkingEvent.content.trim().isEmpty
                      ? 'Analyzing and structuring autonomous solution...'
                      : widget.thinkingEvent.content,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.5,
                    color: cs.onSurface.withAlpha(200),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
