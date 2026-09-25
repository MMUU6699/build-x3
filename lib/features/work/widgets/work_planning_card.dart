import 'package:flutter/material.dart';
import '../../../core/services/work/work_agent_event.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';

/// 1. Planning State Card: Renders the agent's task breakdown and step progress.
class WorkPlanningCard extends StatefulWidget {
  const WorkPlanningCard({super.key, required this.planningEvent});

  final WorkPlanningEvent planningEvent;

  @override
  State<WorkPlanningCard> createState() => _WorkPlanningCardState();
}

class _WorkPlanningCardState extends State<WorkPlanningCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final steps = widget.planningEvent.steps;
    final completedCount = steps
        .where((s) => s.status == WorkPlanStepStatus.completed)
        .length;
    final totalCount = steps.length;
    final allCompleted = totalCount > 0 && completedCount == totalCount;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withAlpha(50), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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
                    allCompleted ? Lucide.CheckCircle2 : Lucide.ListTodo,
                    size: 16,
                    color: allCompleted
                        ? const Color(0xFF10B981)
                        : cs.onSurface,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    allCompleted
                        ? 'Plan completed ($totalCount steps)'
                        : 'Plan: $completedCount of $totalCount completed',
                    style: TextStyle(
                      fontWeight: AppFontWeights.medium,
                      fontSize: 13,
                      color: cs.onSurface,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: allCompleted
                          ? const Color(0xFF10B981).withAlpha(30)
                          : cs.surfaceContainerHighest.withAlpha(120),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$completedCount / $totalCount',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: AppFontWeights.semiBold,
                        color: allCompleted
                            ? const Color(0xFF10B981)
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
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
            Divider(height: 1, color: cs.outline.withAlpha(30)),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: steps
                    .map((step) => _buildStepRow(context, step))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepRow(BuildContext context, WorkPlanStep step) {
    final cs = Theme.of(context).colorScheme;

    Widget indicator;
    TextStyle titleStyle;

    switch (step.status) {
      case WorkPlanStepStatus.completed:
        indicator = Icon(Lucide.CheckCircle2, size: 16, color: cs.onSurface);
        titleStyle = TextStyle(
          fontSize: 13,
          color: cs.onSurfaceVariant,
          decoration: TextDecoration.lineThrough,
        );
        break;
      case WorkPlanStepStatus.inProgress:
        indicator = SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(cs.onSurface),
          ),
        );
        titleStyle = TextStyle(
          fontSize: 13,
          fontWeight: AppFontWeights.medium,
          color: cs.onSurface,
        );
        break;
      case WorkPlanStepStatus.failed:
        indicator = Icon(Lucide.AlertCircle, size: 16, color: Colors.redAccent);
        titleStyle = TextStyle(fontSize: 13, color: Colors.redAccent);
        break;
      case WorkPlanStepStatus.pending:
        indicator = Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: cs.outline.withAlpha(100), width: 1.5),
          ),
        );
        titleStyle = TextStyle(
          fontSize: 13,
          color: cs.onSurfaceVariant.withAlpha(180),
        );
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: indicator),
          const SizedBox(width: 12),
          Expanded(child: Text(step.title, style: titleStyle)),
        ],
      ),
    );
  }
}
