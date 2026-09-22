import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/work_mode_provider.dart';
import '../../../core/services/haptics.dart';
import '../../../core/services/work/work_agent_event.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';
import 'work_deliverable_preview_modal.dart';
import 'work_live_computer_view.dart';

/// Manus-style persistent dockable status panel above the input bar in Work Mode.
/// Matches media_1790076785240.jpg and media_1790076785220.jpg.
class WorkStickyStatusPanel extends StatefulWidget {
  const WorkStickyStatusPanel({super.key});

  @override
  State<WorkStickyStatusPanel> createState() => _WorkStickyStatusPanelState();
}

class _WorkStickyStatusPanelState extends State<WorkStickyStatusPanel>
    with SingleTickerProviderStateMixin {
  bool _expandedChecklist = false;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workProvider = context.watch<WorkModeProvider>();
    if (!workProvider.isWorkMode) return const SizedBox.shrink();

    // Show only when there is an active/recent genuine work task or tool events
    final hasWorkExecution = workProvider.planningEvent != null ||
        workProvider.deliverableEvent != null ||
        workProvider.codingEvents.isNotEmpty ||
        workProvider.terminalEvents.isNotEmpty ||
        workProvider.browsingEvent != null ||
        (workProvider.isExecuting && workProvider.planningEvent != null);

    if (!hasWorkExecution) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bg = isDark
        ? cs.surface.withValues(alpha: 0.94)
        : cs.surface.withValues(alpha: 0.98);
    final border = isDark
        ? cs.outline.withValues(alpha: 0.25)
        : cs.outline.withValues(alpha: 0.15);

    final steps = workProvider.planningEvent?.steps ?? const <WorkPlanStep>[];
    final isExecuting = workProvider.isExecuting;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Collapsed Sticky Pill (media_1790076785240.jpg)
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              Haptics.light();
              WorkLiveComputerView.show(context);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  // Miniature live computer thumbnail
                  const _MiniComputerThumbnail(),
                  const SizedBox(width: 12),

                  // Pulsing blue dot
                  if (isExecuting)
                    FadeTransition(
                      opacity: Tween<double>(begin: 0.4, end: 1.0)
                          .animate(_pulseController),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF3B82F6),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  const SizedBox(width: 8),

                  // Status text: "Working" or "Task Progress"
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isExecuting ? 'Working' : 'Task Progress',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: AppFontWeights.semiBold,
                            color: cs.onSurface,
                          ),
                        ),
                        if (workProvider.activeStep != null)
                          Text(
                            workProvider.activeStep!.title,
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),

                  // Open Deliverable button if ready
                  if (workProvider.hasActiveArtifact) ...[
                    IconButton(
                      icon: Icon(Lucide.ExternalLink, size: 16, color: cs.primary),
                      tooltip: 'Open Deliverable',
                      onPressed: () {
                        Haptics.light();
                        if (workProvider.deliverableEvent != null) {
                          WorkDeliverablePreviewModal.show(
                            context,
                            workProvider.deliverableEvent!,
                          );
                        }
                      },
                    ),
                  ],

                  // Checklist accordion chevron
                  if (steps.isNotEmpty)
                    IconButton(
                      icon: Icon(
                        _expandedChecklist ? Lucide.ChevronDown : Lucide.ChevronRight,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                      tooltip: _expandedChecklist ? 'Collapse Checklist' : 'Expand Checklist',
                      onPressed: () {
                        Haptics.light();
                        setState(() {
                          _expandedChecklist = !_expandedChecklist;
                        });
                      },
                    ),
                ],
              ),
            ),
          ),

          // 2. Expandable Task Progress Checklist (media_1790076785220.jpg)
          if (_expandedChecklist && steps.isNotEmpty) ...[
            Divider(height: 1, color: border),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Task Progress',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: AppFontWeights.medium,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final step in steps) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          step.status == WorkPlanStepStatus.completed
                              ? const Icon(Lucide.Check, size: 14, color: Color(0xFF10B981))
                              : (step.status == WorkPlanStepStatus.inProgress
                                  ? const Icon(Lucide.RefreshCw, size: 14, color: Color(0xFF3B82F6))
                                  : Container(
                                      width: 8,
                                      height: 8,
                                      margin: const EdgeInsets.symmetric(horizontal: 3),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: cs.onSurface.withValues(alpha: 0.25),
                                      ),
                                    )),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              step.title,
                              style: TextStyle(
                                fontSize: 13,
                                color: step.status == WorkPlanStepStatus.completed
                                    ? cs.onSurface
                                    : cs.onSurfaceVariant,
                                decoration: step.status == WorkPlanStepStatus.completed
                                    ? TextDecoration.none
                                    : null,
                              ),
                            ),
                          ),
                        ],
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

/// Miniature 38x28 computer thumbnail showing simulated desktop / code lines.
class _MiniComputerThumbnail extends StatelessWidget {
  const _MiniComputerThumbnail();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 38,
      height: 28,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark ? const Color(0xFF2E2E38) : const Color(0xFFD1D5DB),
          width: 0.8,
        ),
      ),
      padding: const EdgeInsets.all(3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Mini top window dots
          Row(
            children: [
              Container(width: 3, height: 3, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFEF4444))),
              const SizedBox(width: 2),
              Container(width: 3, height: 3, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFF59E0B))),
              const SizedBox(width: 2),
              Container(width: 3, height: 3, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF10B981))),
            ],
          ),
          // Mini code lines
          Container(
            width: 24,
            height: 2,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF4B5563) : const Color(0xFF9CA3AF),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          Container(
            width: 18,
            height: 2,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF3B82F6) : const Color(0xFF60A5FA),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          Container(
            width: 20,
            height: 2,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF4B5563) : const Color(0xFF9CA3AF),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }
}
