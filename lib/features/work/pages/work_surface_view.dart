import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/work_mode_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';
import '../widgets/work_deliverable_card.dart';
import '../widgets/work_live_computer_view.dart';

/// The active workspace canvas for Build X Work Mode.
class WorkSurfaceView extends StatelessWidget {
  const WorkSurfaceView({super.key, this.onSelectPrompt});

  final ValueChanged<String>? onSelectPrompt;

  @override
  Widget build(BuildContext context) {
    final workProvider = context.watch<WorkModeProvider>();
    final cs = Theme.of(context).colorScheme;

    final hasSessionContent =
        workProvider.currentTask.isNotEmpty ||
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
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
                const Icon(
                  Lucide.AlertTriangle,
                  size: 18,
                  color: Colors.redAccent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    workProvider.error!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              ],
            ),
          ),

        if (workProvider.isExecuting ||
            workProvider.computerEvent != null ||
            workProvider.browsingEvent != null ||
            workProvider.codingEvents.isNotEmpty)
          _ActivityCard(
            message: _activityMessage(workProvider),
            onOpenComputer: (workProvider.isExecuting ||
                    workProvider.computerEvent != null ||
                    workProvider.browsingEvent != null ||
                    workProvider.terminalEvents.isNotEmpty ||
                    workProvider.codingEvents.isNotEmpty)
                ? () => WorkLiveComputerView.show(context)
                : null,
          ),

        // Conversational / Direct Response text
        if (workProvider.responseText.isNotEmpty &&
            workProvider.deliverableEvent == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 720),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
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

  String _activityMessage(WorkModeProvider provider) {
    if (provider.isExecuting) {
      final tool = provider.currentToolEvent;
      if (tool != null) {
        return switch (tool.function) {
          'browser_search' => 'Searching the web for your task…',
          'shell_execute' => 'Running a command in the workspace…',
          'file_write' =>
            'Writing ${tool.arguments['path'] ?? 'a workspace file'}…',
          'file_read' => 'Reviewing a workspace file…',
          _ => 'Working in the isolated environment…',
        };
      }
      if (provider.codingEvents.isNotEmpty) return 'Writing project files…';
      if (provider.browsingEvent != null) return 'Researching your task…';
      return 'Preparing the workspace…';
    }
    return 'The live workspace activity is ready to review.';
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

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.message, this.onOpenComputer});

  final String message;
  final VoidCallback? onOpenComputer;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(Lucide.Globe, size: 18, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message, style: TextStyle(color: cs.onSurface)),
            ),
            if (onOpenComputer != null)
              TextButton.icon(
                onPressed: onOpenComputer,
                icon: const Icon(Lucide.Monitor, size: 16),
                label: const Text('Live view'),
              ),
          ],
        ),
      ),
    );
  }
}
