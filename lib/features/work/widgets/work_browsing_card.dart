import 'package:flutter/material.dart';
import '../../../core/services/work/work_agent_event.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';

/// 3. Browsing State Card: Shows live embedded browser view or page snapshot inline.
class WorkBrowsingCard extends StatefulWidget {
  const WorkBrowsingCard({super.key, required this.browsingEvent});

  final WorkBrowsingEvent browsingEvent;

  @override
  State<WorkBrowsingCard> createState() => _WorkBrowsingCardState();
}

class _WorkBrowsingCardState extends State<WorkBrowsingCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final event = widget.browsingEvent;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withAlpha(50), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Browser Window Chrome Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withAlpha(80),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                // Window dots
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withAlpha(40),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withAlpha(40),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withAlpha(40),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                // URL Pill
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: cs.outline.withAlpha(40),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Lucide.Globe,
                          size: 13,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            event.url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  icon: Icon(
                    _expanded ? Lucide.ChevronUp : Lucide.ChevronDown,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Lucide.Compass,
                        size: 14,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          event.title.isNotEmpty
                              ? event.title
                              : 'Live Browser Navigation',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: AppFontWeights.semiBold,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (event.snapshot.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withAlpha(40),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cs.outline.withAlpha(30)),
                      ),
                      child: Text(
                        event.snapshot,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
