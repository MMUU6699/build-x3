import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/work_mode_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';
import '../widgets/work_browsing_card.dart';
import '../widgets/work_coding_card.dart';
import '../widgets/work_deliverable_card.dart';
import '../widgets/work_planning_card.dart';
import '../widgets/work_thinking_card.dart';

/// The active workspace canvas for Build X Work Mode.
class WorkSurfaceView extends StatelessWidget {
  const WorkSurfaceView({
    super.key,
    this.onSelectPrompt,
  });

  final ValueChanged<String>? onSelectPrompt;

  @override
  Widget build(BuildContext context) {
    final workProvider = context.watch<WorkModeProvider>();
    final cs = Theme.of(context).colorScheme;

    final hasSessionContent = workProvider.currentTask.isNotEmpty ||
        workProvider.isExecuting ||
        workProvider.deliverableEvent != null ||
        workProvider.responseText.isNotEmpty ||
        workProvider.planningEvent != null ||
        workProvider.thinkingEvent != null;

    if (!hasSessionContent) {
      return _buildEmptyState(context, workProvider);
    }

    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 120),
      children: [
        // User Task Prompt Header
        if (workProvider.currentTask.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 580),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.onSurface.withAlpha(15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outline.withAlpha(30)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Lucide.Wrench, size: 15, color: cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        workProvider.currentTask,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: AppFontWeights.medium,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Error banner if any
        if (workProvider.error != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.redAccent.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.redAccent.withAlpha(80)),
            ),
            child: Row(
              children: [
                const Icon(Lucide.AlertTriangle, size: 18, color: Colors.redAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    workProvider.error!,
                    style: const TextStyle(fontSize: 13, color: Colors.redAccent),
                  ),
                ),
              ],
            ),
          ),

        // 1. Planning State Card
        if (workProvider.planningEvent != null)
          WorkPlanningCard(planningEvent: workProvider.planningEvent!),

        // 2. Thinking State Card
        if (workProvider.thinkingEvent != null)
          WorkThinkingCard(
            thinkingEvent: workProvider.thinkingEvent!,
            isStreaming: workProvider.isExecuting && workProvider.codingEvents.isEmpty,
          ),

        // 3. Browsing State Card
        if (workProvider.browsingEvent != null)
          WorkBrowsingCard(browsingEvent: workProvider.browsingEvent!),

        // 4. Coding State Cards (File Editor Tool Events)
        for (final coding in workProvider.codingEvents)
          WorkCodingCard(codingEvent: coding),

        // Conversational / Direct Response text
        if (workProvider.responseText.isNotEmpty && workProvider.deliverableEvent == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 720),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.25),
                  ),
                ),
                child: SelectableText(
                  workProvider.responseText,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),
          ),

        // 5. Finished Deliverable Card (Artifact)
        if (workProvider.deliverableEvent != null)
          WorkDeliverableCard(deliverable: workProvider.deliverableEvent!),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, WorkModeProvider workProvider) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          'What do you want to build, change, or create?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: AppFontWeights.regular,
            color: cs.onSurface.withValues(alpha: 0.50),
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}
