import 'package:flutter/material.dart';
import '../../../core/services/work/work_agent_event.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';
import 'work_deliverable_preview_modal.dart';

/// 5. Finished Deliverable Card: Openable/previewable artifact card.
class WorkDeliverableCard extends StatelessWidget {
  const WorkDeliverableCard({
    super.key,
    required this.deliverable,
  });

  final WorkDeliverableEvent deliverable;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: cs.onSurface.withAlpha(50),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withAlpha(70),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.onSurface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Lucide.Sparkles,
                    size: 16,
                    color: cs.surface,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DELIVERABLE ARTIFACT',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: AppFontWeights.bold,
                          letterSpacing: 0.8,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        deliverable.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: AppFontWeights.bold,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (deliverable.summary.isNotEmpty) ...[
                  Text(
                    deliverable.summary,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                // Generated Files Row
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: deliverable.files.map((file) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withAlpha(120),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: cs.outline.withAlpha(30)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Lucide.FileCode, size: 13, color: cs.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Text(
                            file,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                              fontWeight: AppFontWeights.medium,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                // Open / Preview Button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Lucide.ExternalLink, size: 17),
                    label: Text(
                      'Open App / Preview',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: AppFontWeights.semiBold,
                      ),
                    ),
                    onPressed: () {
                      WorkDeliverablePreviewModal.show(context, deliverable);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
