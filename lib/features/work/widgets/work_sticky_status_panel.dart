import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/work_mode_provider.dart';
import '../../../core/services/haptics.dart';
import '../../../core/work_mode_config.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';
import 'work_deliverable_preview_modal.dart';
import 'work_live_computer_view.dart';

/// The only live activity surface kept above the Work composer.
///
/// Detailed browser, terminal and file state lives in [WorkLiveComputerView].
/// This dock intentionally stays compact and uses action labels rather than
/// exposing a plan, URLs, or sandbox implementation details in the chat.
class WorkStickyStatusPanel extends StatefulWidget {
  const WorkStickyStatusPanel({super.key});

  @override
  State<WorkStickyStatusPanel> createState() => _WorkStickyStatusPanelState();
}

class _WorkStickyStatusPanelState extends State<WorkStickyStatusPanel>
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

  bool _hasActivity(WorkModeProvider work) {
    return work.isExecuting ||
        work.hasActiveArtifact ||
        work.browsingEvent != null ||
        work.computerEvent != null ||
        work.currentToolEvent != null ||
        work.codingEvents.isNotEmpty ||
        work.terminalEvents.isNotEmpty ||
        work.error != null;
  }

  String _actionLabel(WorkModeProvider work) {
    final function = work.currentToolEvent?.function.toLowerCase() ?? '';
    if (function.contains('shell') || function.contains('command')) {
      return 'Run a command';
    }
    if (function.contains('file_read') || function == 'read_file') {
      return 'Read file';
    }
    if (function.contains('file_write') ||
        function.contains('file_replace') ||
        function == 'write_file') {
      return 'Write file';
    }
    if (function.contains('file_find') || function.contains('search')) {
      return 'Find files';
    }
    if (function.contains('browser') || work.browsingEvent != null) {
      return 'Browsing';
    }
    if (work.terminalEvents.isNotEmpty) return 'Run a command';
    if (work.codingEvents.isNotEmpty) return 'Write file';
    if (work.computerEvent != null) return 'Using computer';
    return work.hasActiveArtifact || !work.isExecuting ? 'Ready' : 'Working';
  }

  @override
  Widget build(BuildContext context) {
    final work = context.watch<WorkModeProvider>();
    if (!work.isWorkMode) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final hasActivity = _hasActivity(work);
    final isWorking = work.isExecuting;
    final status = isWorking
        ? 'Working'
        : (work.hasActiveArtifact
              ? 'Completed'
              : (hasActivity ? 'Ready' : 'Work computer ready'));

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: cs.outline.withValues(alpha: isDark ? 0.28 : 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.07),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Haptics.light();
          WorkLiveComputerView.show(context);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
          child: Row(
            children: [
              const _LiveComputerThumbnail(),
              const SizedBox(width: 10),
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) => Opacity(
                  opacity: isWorking
                      ? 0.45 + (_pulseController.value * 0.55)
                      : 1,
                  child: child,
                ),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isWorking
                        ? const Color(0xFF2F80ED)
                        : const Color(0xFF10B981),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 14,
                        fontWeight: AppFontWeights.semiBold,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _actionLabel(work),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (work.hasActiveArtifact)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Open result',
                  icon: Icon(Lucide.ExternalLink, size: 17, color: cs.primary),
                  onPressed: () {
                    Haptics.light();
                    final deliverable = work.deliverableEvent;
                    if (deliverable != null) {
                      WorkDeliverablePreviewModal.show(context, deliverable);
                    }
                  },
                ),
              PopupMenuButton<WorkReasoningEffort>(
                tooltip: 'Thinking level',
                onSelected: work.setReasoningEffort,
                itemBuilder: (context) => WorkReasoningEffort.values
                    .map(
                      (effort) => PopupMenuItem<WorkReasoningEffort>(
                        value: effort,
                        child: Row(
                          children: [
                            Icon(
                              Lucide.Brain,
                              size: 16,
                              color: effort == work.reasoningEffort
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Text(effort.displayName),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Lucide.Brain, size: 14, color: cs.primary),
                      const SizedBox(width: 5),
                      Text(
                        'Thinking',
                        style: TextStyle(
                          color: cs.primary,
                          fontSize: 12,
                          fontWeight: AppFontWeights.semiBold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Icon(Lucide.ChevronRight, size: 18, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveComputerThumbnail extends StatelessWidget {
  const _LiveComputerThumbnail();

  @override
  Widget build(BuildContext context) {
    final work = context.watch<WorkModeProvider>();
    final image = work.computerEvent?.screenshotBase64.isNotEmpty == true
        ? work.computerEvent!.screenshotBase64
        : work.browsingEvent?.screenshotBase64;

    if (image != null && image.isNotEmpty) {
      try {
        return _thumbnail(
          context,
          Image.memory(
            base64Decode(image),
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        );
      } catch (_) {
        // Fall through to the honest activity icon if the event had bad data.
      }
    }

    final function = work.currentToolEvent?.function.toLowerCase() ?? '';
    final icon = work.terminalEvents.isNotEmpty || function.contains('shell')
        ? Lucide.Terminal
        : (work.codingEvents.isNotEmpty || function.contains('file')
              ? Lucide.FileCode
              : Lucide.Monitor);
    return _thumbnail(context, Icon(icon, size: 17));
  }

  Widget _thumbnail(BuildContext context, Widget child) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 46,
      height: 32,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outline.withValues(alpha: 0.18)),
      ),
      child: child,
    );
  }
}
