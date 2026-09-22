import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/work_mode_provider.dart';
import '../../../core/services/haptics.dart';
import '../../../core/services/work/work_agent_event.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';
import 'work_deliverable_preview_modal.dart';

/// Full modal screen representing the Manus-style Live Computer & Environment Viewer.
/// Matches media_1790076785237.jpg.
class WorkLiveComputerView extends StatefulWidget {
  const WorkLiveComputerView({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const WorkLiveComputerView(),
    );
  }

  @override
  State<WorkLiveComputerView> createState() => _WorkLiveComputerViewState();
}

class _WorkLiveComputerViewState extends State<WorkLiveComputerView> {
  int _selectedStepIndex = -1; // -1 means "Live" (latest)

  @override
  Widget build(BuildContext context) {
    final workProvider = context.watch<WorkModeProvider>();
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    final steps = workProvider.planningEvent?.steps ?? const <WorkPlanStep>[];
    final totalSteps = steps.isNotEmpty ? steps.length : 1;
    final liveStepIndex = (workProvider.completedSteps < totalSteps)
        ? workProvider.completedSteps
        : totalSteps - 1;
    final currentIndex = (_selectedStepIndex < 0 || _selectedStepIndex >= totalSteps)
        ? liveStepIndex
        : _selectedStepIndex;
    final isAtLive = (_selectedStepIndex < 0 || _selectedStepIndex == liveStepIndex);

    final bg = isDark ? const Color(0xFF141416) : Colors.white;
    final cardBg = isDark ? const Color(0xFF1E1E22) : const Color(0xFFF7F7F8);
    final borderColor = cs.outline.withValues(alpha: isDark ? 0.25 : 0.15);

    return Container(
      height: size.height * 0.90,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Top Header: Close button + Environment status pill
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Lucide.X, size: 20, color: cs.onSurface),
                  tooltip: 'Close',
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Lucide.Cpu, size: 14, color: cs.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Build X Autonomous Environment',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: AppFontWeights.medium,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                const SizedBox(width: 40),
              ],
            ),
          ),

          // Main Viewport: Live tool output / computer screen
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Tool window titlebar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: borderColor)),
                      ),
                      child: Row(
                        children: [
                          Icon(Lucide.Terminal, size: 16, color: cs.primary),
                          const SizedBox(width: 8),
                          Text(
                            'build_x_agent',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: AppFontWeights.semiBold,
                              fontFamily: 'monospace',
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'task.execute',
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          if (workProvider.hasActiveArtifact)
                            GestureDetector(
                              onTap: () {
                                if (workProvider.deliverableEvent != null) {
                                  WorkDeliverablePreviewModal.show(
                                    context,
                                    workProvider.deliverableEvent!,
                                  );
                                }
                              },
                              child: Row(
                                children: [
                                  Icon(Lucide.ExternalLink, size: 13, color: cs.primary),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Open Artifact',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: AppFontWeights.medium,
                                      color: cs.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Content Viewer
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: _buildViewportContent(
                          context,
                          workProvider: workProvider,
                          currentStepIndex: currentIndex,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom Bar: Status description, scrubber slider & media controls
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: borderColor)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Tool status description
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Lucide.Wrench, size: 16, color: cs.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            workProvider.isExecuting
                                ? 'Build X is running ${steps.isNotEmpty ? steps[currentIndex.clamp(0, steps.length - 1)].title : 'task'}'
                                : 'Task completed: ${steps.isNotEmpty ? steps.last.title : 'Ready'}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: AppFontWeights.medium,
                              color: cs.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Step ${currentIndex + 1} of $totalSteps',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Scrubber Slider
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: cs.primary,
                    inactiveTrackColor: cs.outline.withValues(alpha: 0.20),
                    thumbColor: cs.primary,
                  ),
                  child: Slider(
                    value: currentIndex.toDouble().clamp(0.0, (totalSteps - 1).toDouble()),
                    min: 0,
                    max: (totalSteps - 1).toDouble(),
                    divisions: totalSteps > 1 ? totalSteps - 1 : 1,
                    onChanged: (val) {
                      Haptics.light();
                      setState(() {
                        _selectedStepIndex = val.round();
                      });
                    },
                  ),
                ),

                const SizedBox(height: 6),

                // Step Controls: [|◀] [● Live] [▶|]
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(Lucide.ChevronLeft, size: 22, color: cs.onSurface),
                      tooltip: 'Previous Step',
                      onPressed: currentIndex > 0
                          ? () {
                              Haptics.light();
                              setState(() {
                                _selectedStepIndex = currentIndex - 1;
                              });
                            }
                          : null,
                    ),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: () {
                        Haptics.light();
                        setState(() {
                          _selectedStepIndex = -1; // Return to Live
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: isAtLive
                              ? cs.primary.withValues(alpha: 0.15)
                              : cs.onSurface.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isAtLive ? cs.primary : borderColor,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isAtLive ? const Color(0xFF10B981) : cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Live',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: AppFontWeights.semiBold,
                                color: isAtLive ? const Color(0xFF10B981) : cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: Icon(Lucide.ChevronRight, size: 22, color: cs.onSurface),
                      tooltip: 'Next Step',
                      onPressed: currentIndex < totalSteps - 1
                          ? () {
                              Haptics.light();
                              setState(() {
                                _selectedStepIndex = currentIndex + 1;
                              });
                            }
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewportContent(
    BuildContext context, {
    required WorkModeProvider workProvider,
    required int currentStepIndex,
    required bool isDark,
  }) {
    final cs = Theme.of(context).colorScheme;

    // 1. If deliverable exists and we are at last step
    if (workProvider.hasActiveArtifact &&
        (currentStepIndex >= (workProvider.totalSteps - 1))) {
      final deliverable = workProvider.deliverableEvent!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Lucide.Globe, size: 16, color: Color(0xFF10B981)),
              const SizedBox(width: 8),
              Text(
                deliverable.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: AppFontWeights.semiBold,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Entrypoint: ${deliverable.entrypoint}',
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.black : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
            ),
            child: Text(
              deliverable.previewHtml.length > 800
                  ? '${deliverable.previewHtml.substring(0, 800)}\n\n/* ... deliverable continues ... */'
                  : deliverable.previewHtml,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: cs.onSurface.withValues(alpha: 0.9),
                height: 1.4,
              ),
            ),
          ),
        ],
      );
    }

    // 2. If coding event exists
    if (workProvider.codingEvents.isNotEmpty) {
      final coding = workProvider.codingEvents.last;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '// File: ${coding.filePath}',
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.black : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
            ),
            child: Text(
              coding.newContent.length > 700
                  ? '${coding.newContent.substring(0, 700)}\n\n/* ... */'
                  : coding.newContent,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: cs.onSurface.withValues(alpha: 0.9),
                height: 1.4,
              ),
            ),
          ),
        ],
      );
    }

    // 3. Fallback: reasoning/thinking or step title
    final thinking = workProvider.thinkingEvent?.content ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Agent Live Execution Trace:',
          style: TextStyle(
            fontSize: 13,
            fontWeight: AppFontWeights.medium,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          thinking.isNotEmpty
              ? thinking
              : 'Executing autonomous planning & code generation...',
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
