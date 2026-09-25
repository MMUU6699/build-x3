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
  String? _activeTab; // null (auto-sync), 'preview', 'code', 'terminal'

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
    final currentIndex =
        (_selectedStepIndex < 0 || _selectedStepIndex >= totalSteps)
        ? liveStepIndex
        : _selectedStepIndex;
    final isAtLive =
        (_selectedStepIndex < 0 || _selectedStepIndex == liveStepIndex);

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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
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
                    Builder(
                      builder: (context) {
                        final effectiveTab = _getEffectiveTab(
                          workProvider,
                          currentIndex,
                        );
                        final toolInfo = _getActiveToolInfo(
                          workProvider,
                          currentIndex,
                          effectiveTab,
                        );
                        final hasPreview =
                            workProvider.hasActiveArtifact ||
                            workProvider.deliverableEvent != null;
                        final hasCode = workProvider.codingEvents.isNotEmpty;
                        final hasTerminal =
                            workProvider.terminalEvents.isNotEmpty;
                        final showTabs =
                            [
                              hasPreview,
                              hasCode,
                              hasTerminal,
                            ].where((b) => b).length >=
                            2;

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: borderColor),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(toolInfo.$1, size: 16, color: cs.primary),
                              const SizedBox(width: 8),
                              Text(
                                toolInfo.$2,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: AppFontWeights.semiBold,
                                  fontFamily: 'monospace',
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                toolInfo.$3,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              if (showTabs) ...[
                                if (hasPreview)
                                  _buildTabChip(
                                    context,
                                    label: 'Preview',
                                    icon: Lucide.Globe,
                                    isSelected: effectiveTab == 'preview',
                                    onTap: () {
                                      Haptics.light();
                                      setState(() => _activeTab = 'preview');
                                    },
                                  ),
                                if (hasCode)
                                  _buildTabChip(
                                    context,
                                    label: 'Code',
                                    icon: Lucide.Code,
                                    isSelected: effectiveTab == 'code',
                                    onTap: () {
                                      Haptics.light();
                                      setState(() => _activeTab = 'code');
                                    },
                                  ),
                                if (hasTerminal)
                                  _buildTabChip(
                                    context,
                                    label: 'Terminal',
                                    icon: Lucide.Terminal,
                                    isSelected: effectiveTab == 'terminal',
                                    onTap: () {
                                      Haptics.light();
                                      setState(() => _activeTab = 'terminal');
                                    },
                                  ),
                                const SizedBox(width: 8),
                              ],
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
                                      Icon(
                                        Lucide.ExternalLink,
                                        size: 13,
                                        color: cs.primary,
                                      ),
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
                        );
                      },
                    ),

                    // Content Viewer: High-fidelity tool renderers
                    Expanded(
                      child: _buildViewportContent(
                        context,
                        workProvider: workProvider,
                        currentStepIndex: currentIndex,
                        isDark: isDark,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Tool status description
                Builder(
                  builder: (context) {
                    final toolInfo = _getActiveToolInfo(
                      workProvider,
                      currentIndex,
                    );
                    return Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(toolInfo.$1, size: 16, color: cs.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getStepActionDescription(
                                  workProvider,
                                  currentIndex,
                                  steps,
                                ),
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
                    );
                  },
                ),

                const SizedBox(height: 12),

                // Scrubber Slider
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                    activeTrackColor: cs.primary,
                    inactiveTrackColor: cs.outline.withValues(alpha: 0.20),
                    thumbColor: cs.primary,
                  ),
                  child: Slider(
                    value: currentIndex.toDouble().clamp(
                      0.0,
                      (totalSteps - 1).toDouble(),
                    ),
                    min: 0,
                    max: (totalSteps - 1).toDouble(),
                    divisions: totalSteps > 1 ? totalSteps - 1 : 1,
                    onChanged: (val) {
                      Haptics.light();
                      setState(() {
                        _selectedStepIndex = val.round();
                        _activeTab = null;
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
                      icon: Icon(
                        Lucide.ChevronLeft,
                        size: 22,
                        color: cs.onSurface,
                      ),
                      tooltip: 'Previous Step',
                      onPressed: currentIndex > 0
                          ? () {
                              Haptics.light();
                              setState(() {
                                _selectedStepIndex = currentIndex - 1;
                                _activeTab = null;
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
                          _activeTab = null;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
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
                                color: isAtLive
                                    ? const Color(0xFF10B981)
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Live',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: AppFontWeights.semiBold,
                                color: isAtLive
                                    ? const Color(0xFF10B981)
                                    : cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: Icon(
                        Lucide.ChevronRight,
                        size: 22,
                        color: cs.onSurface,
                      ),
                      tooltip: 'Next Step',
                      onPressed: currentIndex < totalSteps - 1
                          ? () {
                              Haptics.light();
                              setState(() {
                                _selectedStepIndex = currentIndex + 1;
                                _activeTab = null;
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

  String? _getEffectiveTab(
    WorkModeProvider workProvider,
    int currentStepIndex,
  ) {
    if (_activeTab != null) return _activeTab;
    if (workProvider.hasActiveArtifact &&
        (currentStepIndex >= (workProvider.totalSteps - 1))) {
      return 'preview';
    }
    if (workProvider.terminalEvents.isNotEmpty && currentStepIndex >= 2) {
      return 'terminal';
    }
    if (workProvider.codingEvents.isNotEmpty && currentStepIndex >= 2) {
      return 'code';
    }
    return null;
  }

  (IconData, String, String) _getActiveToolInfo(
    WorkModeProvider workProvider,
    int currentStepIndex, [
    String? effectiveTab,
  ]) {
    final tab =
        effectiveTab ?? _getEffectiveTab(workProvider, currentStepIndex);
    if (tab == 'preview' &&
        (workProvider.hasActiveArtifact ||
            workProvider.deliverableEvent != null)) {
      return (Lucide.Globe, 'browser', 'preview.serve');
    }
    if (tab == 'terminal' && workProvider.terminalEvents.isNotEmpty) {
      return (Lucide.Terminal, 'terminal', 'bash.exec');
    }
    if (tab == 'code' && workProvider.codingEvents.isNotEmpty) {
      return (Lucide.Code, 'code_editor', 'file.write');
    }
    if (workProvider.hasActiveArtifact &&
        (currentStepIndex >= (workProvider.totalSteps - 1))) {
      return (Lucide.Globe, 'browser', 'preview.serve');
    }
    if (workProvider.terminalEvents.isNotEmpty && currentStepIndex >= 2) {
      return (Lucide.Terminal, 'terminal', 'bash.exec');
    }
    if (workProvider.codingEvents.isNotEmpty && currentStepIndex >= 2) {
      return (Lucide.Code, 'code_editor', 'file.write');
    }
    if (workProvider.browsingEvent != null || currentStepIndex == 1) {
      return (Lucide.Search, 'web_search', 'search.query');
    }
    return (Lucide.Cpu, 'build_x_host', 'agent.idle');
  }

  Widget _buildTabChip(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? cs.primary.withValues(alpha: 0.4)
                : Colors.transparent,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: isSelected ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected
                    ? AppFontWeights.semiBold
                    : AppFontWeights.medium,
                color: isSelected ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getStepActionDescription(
    WorkModeProvider workProvider,
    int currentStepIndex,
    List<WorkPlanStep> steps,
  ) {
    if (!workProvider.isExecuting) {
      if (workProvider.hasActiveArtifact) {
        return 'Deliverable ready for preview';
      }
      return 'Task completed';
    }

    if (workProvider.hasActiveArtifact &&
        (currentStepIndex >= (workProvider.totalSteps - 1))) {
      return 'Serving interactive deliverable…';
    }
    if (workProvider.terminalEvents.isNotEmpty && currentStepIndex >= 2) {
      return 'Packaging web application bundle…';
    }
    if (workProvider.codingEvents.isNotEmpty && currentStepIndex >= 2) {
      final file = workProvider.codingEvents.last.filePath;
      return 'Generating source code: $file…';
    }
    if (workProvider.browsingEvent != null || currentStepIndex == 1) {
      return 'Researching web specifications & architecture…';
    }
    if (steps.isNotEmpty && currentStepIndex < steps.length) {
      return steps[currentStepIndex].title;
    }
    return 'Analyzing task requirements…';
  }

  Widget _buildViewportContent(
    BuildContext context, {
    required WorkModeProvider workProvider,
    required int currentStepIndex,
    required bool isDark,
  }) {
    final cs = Theme.of(context).colorScheme;
    final borderColor = cs.outline.withValues(alpha: isDark ? 0.25 : 0.15);
    final effectiveTab = _getEffectiveTab(workProvider, currentStepIndex);

    // Tab-directed or step-directed resolution:
    if (effectiveTab == 'preview' &&
        (workProvider.hasActiveArtifact ||
            workProvider.deliverableEvent != null)) {
      final deliverable = workProvider.deliverableEvent!;
      return _buildBrowserVisualView(
        context,
        url: 'http://localhost:5173/${deliverable.entrypoint}',
        title: deliverable.title,
        previewHtml: deliverable.previewHtml,
        isDark: isDark,
        borderColor: borderColor,
      );
    }

    if (effectiveTab == 'terminal' && workProvider.terminalEvents.isNotEmpty) {
      return _buildTerminalConsoleVisualView(
        context,
        terminal: workProvider.terminalEvents.last,
        borderColor: borderColor,
      );
    }

    if (effectiveTab == 'code' && workProvider.codingEvents.isNotEmpty) {
      return _buildCodeEditorVisualView(
        context,
        coding: workProvider.codingEvents.last,
        isDark: isDark,
        borderColor: borderColor,
      );
    }

    // Fallbacks:
    // 1. Deliverable ready / App preview
    if (workProvider.hasActiveArtifact &&
        (currentStepIndex >= (workProvider.totalSteps - 1))) {
      final deliverable = workProvider.deliverableEvent!;
      return _buildBrowserVisualView(
        context,
        url: 'http://localhost:5173/${deliverable.entrypoint}',
        title: deliverable.title,
        previewHtml: deliverable.previewHtml,
        isDark: isDark,
        borderColor: borderColor,
      );
    }

    // 2. Terminal execution
    if (workProvider.terminalEvents.isNotEmpty && currentStepIndex >= 2) {
      return _buildTerminalConsoleVisualView(
        context,
        terminal: workProvider.terminalEvents.last,
        borderColor: borderColor,
      );
    }

    // 3. Coding view
    if (workProvider.codingEvents.isNotEmpty && currentStepIndex >= 2) {
      return _buildCodeEditorVisualView(
        context,
        coding: workProvider.codingEvents.last,
        isDark: isDark,
        borderColor: borderColor,
      );
    }

    // 4. Browser / Research view
    if (workProvider.browsingEvent != null || currentStepIndex == 1) {
      final browsing = workProvider.browsingEvent;
      return _buildBrowserVisualView(
        context,
        url: browsing?.url ?? 'https://docs.webcontainers.io',
        title: browsing?.title ?? 'Web Development Reference & APIs',
        previewHtml: browsing?.snapshot,
        isDark: isDark,
        borderColor: borderColor,
      );
    }

    // 5. Search view during early analysis or when executing
    if (workProvider.isExecuting) {
      return _buildSearchVisualView(
        context,
        workProvider: workProvider,
        isDark: isDark,
        borderColor: borderColor,
      );
    }

    // 6. Idle Workstation
    return _buildIdleComputerVisualView(
      context,
      isDark: isDark,
      borderColor: borderColor,
    );
  }

  Widget _buildBrowserVisualView(
    BuildContext context, {
    required String url,
    required String title,
    required String? previewHtml,
    required bool isDark,
    required Color borderColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    final addressBg = isDark
        ? const Color(0xFF14171F)
        : const Color(0xFFEFF1F5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Browser Address Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1D26) : const Color(0xFFF3F4F6),
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          child: Row(
            children: [
              Icon(
                Lucide.ArrowLeft,
                size: 14,
                color: cs.onSurface.withValues(alpha: 0.35),
              ),
              const SizedBox(width: 8),
              Icon(
                Lucide.ArrowRight,
                size: 14,
                color: cs.onSurface.withValues(alpha: 0.35),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => Haptics.light(),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Lucide.RotateCw,
                    size: 14,
                    color: cs.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // URL bar
              Expanded(
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: addressBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Lucide.Lock,
                        size: 11,
                        color: Color(0xFF10B981),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          url,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: cs.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // "Take Control" Manus action button
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  Haptics.light();
                  final work = context.read<WorkModeProvider>();
                  if (work.deliverableEvent != null) {
                    WorkDeliverablePreviewModal.show(
                      context,
                      work.deliverableEvent!,
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Browser sandbox interactive mode active',
                        ),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFF3B82F6),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Lucide.Sparkles,
                        size: 12,
                        color: Color(0xFF3B82F6),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Take Control',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: AppFontWeights.semiBold,
                          color: const Color(0xFF3B82F6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Browser Webpage Content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Page header card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF18181C) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.2 : 0.05,
                        ),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF10B981,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                                const SizedBox(width: 5),
                                const Text(
                                  'HTTP 200 OK',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'WebContainer Runtime',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        title.isNotEmpty
                            ? title
                            : 'Deliverable Application Preview',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: AppFontWeights.bold,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Interactive client-side web application bundle compiled and executing in autonomous WebContainer sandbox.',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        onPressed: () {
                          Haptics.light();
                          final work = context.read<WorkModeProvider>();
                          if (work.deliverableEvent != null) {
                            WorkDeliverablePreviewModal.show(
                              context,
                              work.deliverableEvent!,
                            );
                          }
                        },
                        icon: const Icon(Lucide.ExternalLink, size: 14),
                        label: const Text('Open Interactive Deliverable'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (previewHtml != null && previewHtml.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Compiled DOM / Source Tree',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: AppFontWeights.medium,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF111113)
                          : const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: borderColor),
                    ),
                    child: Text(
                      previewHtml.length > 500
                          ? '${previewHtml.substring(0, 500)}\n\n/* ... full standalone app bundle ... */'
                          : previewHtml,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.85),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCodeEditorVisualView(
    BuildContext context, {
    required WorkCodingEvent coding,
    required bool isDark,
    required Color borderColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    final lines = coding.newContent.split('\n');
    final editorBg = isDark ? const Color(0xFF111216) : const Color(0xFFF9FAFB);
    final gutterColor = isDark
        ? const Color(0xFF4B5563)
        : const Color(0xFF9CA3AF);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Editor Tabs Header
        Container(
          padding: const EdgeInsets.only(left: 10, top: 4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF16181F) : const Color(0xFFE5E7EB),
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: editorBg,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8),
                  ),
                  border: Border(
                    top: BorderSide(color: const Color(0xFF3B82F6), width: 2),
                    left: BorderSide(color: borderColor),
                    right: BorderSide(color: borderColor),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Lucide.FileCode,
                      size: 13,
                      color: Color(0xFF3B82F6),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      coding.filePath,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontWeight: AppFontWeights.medium,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: 12, bottom: 4),
                child: Row(
                  children: [
                    Text(
                      'UTF-8',
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      coding.filePath.endsWith('.html') ? 'HTML' : 'JS',
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Code Content with Line Numbers
        Expanded(
          child: Container(
            color: editorBg,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Line Numbers Column
                  Container(
                    width: 38,
                    padding: const EdgeInsets.only(right: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(
                        lines.length.clamp(1, 100),
                        (idx) => Text(
                          '${idx + 1}',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: gutterColor,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: (lines.length.clamp(1, 100) * 16.0),
                    color: borderColor,
                  ),
                  const SizedBox(width: 10),
                  // Code Lines Column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(lines.length.clamp(1, 100), (
                        idx,
                      ) {
                        final line = lines[idx];
                        return Text(
                          line.isNotEmpty ? line : ' ',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: _getCodeLineColor(line, isDark),
                            height: 1.45,
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Editor Status Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF16181F) : const Color(0xFFE5E7EB),
            border: Border(top: BorderSide(color: borderColor)),
          ),
          child: Row(
            children: [
              Text(
                'Ln ${lines.length}, Col 1',
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Spaces: 2',
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              const Icon(
                Lucide.CheckCircle,
                size: 11,
                color: Color(0xFF10B981),
              ),
              const SizedBox(width: 4),
              Text(
                'Syntax Valid',
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getCodeLineColor(String line, bool isDark) {
    final trimmed = line.trim();
    if (trimmed.startsWith('//') ||
        trimmed.startsWith('/*') ||
        trimmed.startsWith('*') ||
        trimmed.startsWith('<!--')) {
      return const Color(0xFF6B7280); // Comment gray
    }
    if (trimmed.startsWith('<') || trimmed.endsWith('>')) {
      return isDark
          ? const Color(0xFF60A5FA)
          : const Color(0xFF2563EB); // Tag blue
    }
    if (trimmed.startsWith('import ') ||
        trimmed.startsWith('export ') ||
        trimmed.startsWith('function') ||
        trimmed.startsWith('const ') ||
        trimmed.startsWith('let ')) {
      return isDark
          ? const Color(0xFFF472B6)
          : const Color(0xFFDB2777); // Keyword pink
    }
    if (trimmed.contains('{') || trimmed.contains('}')) {
      return isDark
          ? const Color(0xFFFBBF24)
          : const Color(0xFFD97706); // Structure amber
    }
    return isDark
        ? const Color(0xFFE5E7EB)
        : const Color(0xFF1F2937); // Default
  }

  Widget _buildTerminalConsoleVisualView(
    BuildContext context, {
    required WorkTerminalEvent terminal,
    required Color borderColor,
  }) {
    const termBg = Color(0xFF0D1117);

    return Container(
      color: termBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mac-style Terminal Title Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFF59E0B),
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF10B981),
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'bash - buildx-sandbox (80x24)',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Color(0xFF8B949E),
                  ),
                ),
              ],
            ),
          ),
          // Terminal Output Stream
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Build X WebContainer v1.0.0 (x86_64-linux)',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFF8B949E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Executed command
                  Row(
                    children: [
                      const Text(
                        'buildx@sandbox:~/app\$ ',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF58A6FF),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          terminal.command,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Color(0xFFF0F6FC),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Command output
                  Text(
                    terminal.output,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFF7EE787),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Cursor
                  Row(
                    children: [
                      const Text(
                        'buildx@sandbox:~/app\$ ',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF58A6FF),
                        ),
                      ),
                      Container(
                        width: 8,
                        height: 14,
                        color: const Color(0xFF58A6FF),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchVisualView(
    BuildContext context, {
    required WorkModeProvider workProvider,
    required bool isDark,
    required Color borderColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    final taskTitle = workProvider.currentTask.isNotEmpty
        ? workProvider.currentTask
        : 'Web Development Components & Runtime';

    final searchResults = [
      (
        'https://docs.webcontainers.io/reference/runtime',
        'WebContainers Runtime Specifications & In-Browser Node.js',
        'Official architecture and performance guide for executing client-side containerized applications, POSIX file system APIs, and live server loops.',
      ),
      (
        'https://developer.mozilla.org/en-US/docs/Web/API',
        'Modern Web APIs and Component Architecture Standards',
        'Comprehensive documentation for HTML5, Web Components, Service Workers, Canvas rendering, and modern ES module dynamic loading.',
      ),
      (
        'https://github.com/stackblitz/webcontainer-core',
        'Autonomous Agent Tool Execution & Sandbox Containers',
        'Sandboxed virtualized process environment for running code generation agents securely within modern browser runtimes.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search bar header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF18181C) : const Color(0xFFF3F4F6),
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF111113) : Colors.white,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Icon(Lucide.Search, size: 14, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    taskTitle,
                    style: TextStyle(fontSize: 12, color: cs.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Lucide.X, size: 14, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
        // Search Results List
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: searchResults.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = searchResults[index];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF18181C) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.$1,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF10B981),
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.$2,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: AppFontWeights.semiBold,
                        color: const Color(0xFF3B82F6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.$3,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildIdleComputerVisualView(
    BuildContext context, {
    required bool isDark,
    required Color borderColor,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E1E24)
                    : const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: Icon(Lucide.Cpu, size: 30, color: cs.primary),
            ),
            const SizedBox(height: 16),
            Text(
              'Build X Autonomous Workstation',
              style: TextStyle(
                fontSize: 15,
                fontWeight: AppFontWeights.semiBold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Sandbox runtime ready. Standing by for autonomous instructions.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildChip(
                  context,
                  Lucide.Shield,
                  'Sandboxed Runtime',
                  borderColor,
                ),
                _buildChip(
                  context,
                  Lucide.Globe,
                  'WebContainers Enabled',
                  borderColor,
                ),
                _buildChip(
                  context,
                  Lucide.Bot,
                  'NVIDIA Nemotron 3 Ultra',
                  borderColor,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(
    BuildContext context,
    IconData icon,
    String text,
    Color borderColor,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: cs.primary),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(fontSize: 11, color: cs.onSurface)),
        ],
      ),
    );
  }
}
