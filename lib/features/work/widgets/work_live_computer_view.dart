import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
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
  const WorkLiveComputerView({super.key, this.sidePanel = false});

  final bool sidePanel;

  static void show(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 720;
    if (isWide) {
      showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Close computer',
        barrierColor: Colors.black.withValues(alpha: 0.28),
        pageBuilder: (context, _, __) => Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: math
                .min(620.0, MediaQuery.sizeOf(context).width * 0.72)
                .toDouble(),
            height: MediaQuery.sizeOf(context).height,
            child: const WorkLiveComputerView(sidePanel: true),
          ),
        ),
      );
      return;
    }
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
  String? _activeTab; // null (auto-sync), 'browser', 'terminal', 'files'
  bool _takeoverEnabled = false;
  bool _controlInFlight = false;
  final TextEditingController _controlTextController = TextEditingController();

  @override
  void dispose() {
    _controlTextController.dispose();
    super.dispose();
  }

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
      // Keep the computer surface nearly full-screen so the live browser is
      // not reduced to a decorative half-height preview.
      height: widget.sidePanel ? size.height : size.height * 0.96,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: widget.sidePanel
            ? const BorderRadius.horizontal(left: Radius.circular(24))
            : const BorderRadius.vertical(top: Radius.circular(24)),
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

          // Top Header: Close button + "Build X's computer" + [ 🖥️ v ] dropdown
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Lucide.X, size: 20, color: cs.onSurface),
                  tooltip: 'Close',
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      "Build X's computer",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: AppFontWeights.semiBold,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Display Mode',
                  onSelected: (mode) {
                    Haptics.light();
                    setState(() {
                      _activeTab = mode == 'auto' ? null : mode;
                    });
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'auto', child: Text('Auto')),
                    const PopupMenuItem(
                      value: 'browser',
                      child: Text('Browser'),
                    ),
                    const PopupMenuItem(
                      value: 'terminal',
                      child: Text('Terminal'),
                    ),
                    const PopupMenuItem(value: 'editor', child: Text('Files')),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Lucide.Monitor, size: 16, color: cs.onSurface),
                        const SizedBox(width: 4),
                        Icon(
                          Lucide.ChevronDown,
                          size: 14,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
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
                child: _buildViewportContent(
                  context,
                  workProvider: workProvider,
                  currentStepIndex: currentIndex,
                  isDark: isDark,
                  visualState: _resolveVisualState(workProvider, currentIndex),
                  borderColor: borderColor,
                ),
              ),
            ),
          ),

          // Bottom Bar: Action Tile, scrubber slider & media controls
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Action Tile (below viewport card)
                Builder(
                  builder: (context) {
                    final currentVisualState = _resolveVisualState(
                      workProvider,
                      currentIndex,
                    );
                    final (icon, title, subtitle) = _resolveActionTileContent(
                      currentVisualState,
                      workProvider,
                    );

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF27272A)
                                  : const Color(0xFFF4F4F5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              icon,
                              size: 20,
                              color: cs.onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: AppFontWeights.bold,
                                    color: cs.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 4),

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

                // Step Controls: [|◀] [● Live / ▶ Jump to live] [▶|]
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.skip_previous,
                        size: 26,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                      tooltip: 'Previous / Start',
                      onPressed: currentIndex > 0
                          ? () {
                              Haptics.light();
                              setState(() {
                                _selectedStepIndex = currentIndex - 1;
                              });
                            }
                          : null,
                    ),
                    if (isAtLive)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF10B981),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Live',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ],
                      )
                    else
                      GestureDetector(
                        onTap: () {
                          Haptics.light();
                          setState(() {
                            _selectedStepIndex = -1; // Return to Live
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF27272A)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: borderColor),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.25 : 0.08,
                                ),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Lucide.Play, size: 12, color: cs.onSurface),
                              const SizedBox(width: 6),
                              Text(
                                'Jump to live',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: AppFontWeights.semiBold,
                                  color: cs.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    IconButton(
                      icon: Icon(
                        Icons.skip_next,
                        size: 26,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                      tooltip: 'Next / End',
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

  Future<void> _sendBrowserControl(
    String action, {
    double? x,
    double? y,
    String? key,
    String? code,
    String? text,
    String? direction,
  }) async {
    if (!_takeoverEnabled || _controlInFlight) return;
    setState(() => _controlInFlight = true);
    final ok = await context.read<WorkModeProvider>().controlBrowser(
      action: action,
      x: x,
      y: y,
      key: key,
      code: code,
      text: text,
      direction: direction,
    );
    if (!mounted) return;
    setState(() => _controlInFlight = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Live browser control is unavailable.')),
      );
    }
  }

  void _toggleTakeover() {
    Haptics.light();
    setState(() => _takeoverEnabled = !_takeoverEnabled);
  }

  void _handleBrowserTap(Offset localPosition, Size viewportSize) {
    // Chromium is started with a 1280x900 viewport. Map the displayed image
    // back to that viewport so taps become real CDP mouse events.
    final scale = math.min(
      viewportSize.width / 1280,
      viewportSize.height / 900,
    );
    if (scale <= 0) return;
    final rendered = Size(1280 * scale, 900 * scale);
    final dx =
        ((localPosition.dx - (viewportSize.width - rendered.width) / 2) / scale)
            .clamp(0.0, 1280.0);
    final dy =
        ((localPosition.dy - (viewportSize.height - rendered.height) / 2) /
                scale)
            .clamp(0.0, 900.0);
    unawaited(_sendBrowserControl('mouse_click', x: dx, y: dy));
  }

  String _resolveVisualState(
    WorkModeProvider workProvider,
    int currentStepIndex,
  ) {
    if (_activeTab != null && _activeTab != 'auto') return _activeTab!;
    if (workProvider.browsingEvent != null ||
        workProvider.currentToolEvent?.name == 'browser') {
      return 'browser';
    }
    if (workProvider.terminalEvents.isNotEmpty ||
        workProvider.currentToolEvent?.name == 'shell') {
      return 'terminal';
    }
    if (workProvider.codingEvents.isNotEmpty ||
        workProvider.currentToolEvent?.name == 'file') {
      return 'editor';
    }
    if (workProvider.isExecuting &&
        workProvider.thinkingEvent?.status == 'running') {
      return 'thinking';
    }
    if (workProvider.computerEvent?.screenshotBase64.isNotEmpty == true) {
      return 'browser';
    }
    if (workProvider.hasActiveArtifact) {
      return 'browser';
    }
    return 'browser';
  }

  (IconData, String, String) _resolveActionTileContent(
    String visualState,
    WorkModeProvider workProvider,
  ) {
    if (visualState == 'browser') {
      final url =
          workProvider.browsingEvent?.url ??
          workProvider.computerEvent?.url ??
          'about:blank';
      return (Lucide.Compass, 'Build X is using Browser', 'Browsing: $url');
    }
    if (visualState == 'terminal') {
      final cmd = workProvider.terminalEvents.isNotEmpty
          ? workProvider.terminalEvents.last.command
          : 'ubuntu@buildx-sandbox:~\$';
      return (Lucide.Terminal, 'Run commands', cmd);
    }
    if (visualState == 'editor') {
      final file = workProvider.codingEvents.isNotEmpty
          ? workProvider.codingEvents.last.filePath
          : 'workspace/index.html';
      final operation = workProvider.codingEvents.isNotEmpty
          ? workProvider.codingEvents.last.operation
          : '';
      final verb = operation == 'read' ? 'Read file' : 'Write file';
      return (Lucide.FileCode, verb, file);
    }
    if (visualState == 'thinking') {
      return (Lucide.Brain, 'Thinking', 'Working through the next action…');
    }
    return (
      Lucide.Compass,
      'Build X is using Browser',
      'Waiting for a live browser frame',
    );
  }

  Widget _buildViewportContent(
    BuildContext context, {
    required WorkModeProvider workProvider,
    required int currentStepIndex,
    required bool isDark,
    required String visualState,
    required Color borderColor,
  }) {
    if (visualState == 'thinking') {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 14),
            Text(
              'Thinking',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: AppFontWeights.semiBold,
              ),
            ),
          ],
        ),
      );
    }
    if (visualState == 'browser') {
      final browsing = workProvider.browsingEvent;
      final deliverable = workProvider.deliverableEvent;
      final url =
          browsing?.url ??
          (workProvider.computerEvent?.url.isNotEmpty == true
              ? workProvider.computerEvent!.url
              : null) ??
          (deliverable != null
              ? 'sandbox://workspace/${deliverable.entrypoint}'
              : 'about:blank');
      final title =
          browsing?.title ??
          workProvider.computerEvent?.title ??
          (deliverable?.title ?? 'Live browser');
      final previewHtml = deliverable?.previewHtml ?? browsing?.snapshot;

      return _buildBrowserVisualView(
        context,
        url: url,
        title: title,
        previewHtml: previewHtml,
        screenshotBase64: browsing?.screenshotBase64.isNotEmpty == true
            ? browsing!.screenshotBase64
            : workProvider.computerEvent?.screenshotBase64,
        isDark: isDark,
        borderColor: borderColor,
      );
    }

    if (visualState == 'terminal') {
      final terminal = workProvider.terminalEvents.isNotEmpty
          ? workProvider.terminalEvents.last
          : const WorkTerminalEvent(
              command: 'No recorded terminal command',
              output: 'No terminal event has been recorded for this run yet.',
            );

      return _buildTerminalConsoleVisualView(
        context,
        terminal: terminal,
        borderColor: borderColor,
        isDark: isDark,
      );
    }

    if (visualState == 'editor') {
      final coding = workProvider.codingEvents.isNotEmpty
          ? workProvider.codingEvents.last
          : const WorkCodingEvent(
              filePath: 'No recorded file',
              oldContent: '',
              newContent: 'No file update has been recorded for this run yet.',
            );

      return _buildCodeEditorVisualView(
        context,
        coding: coding,
        isDark: isDark,
        borderColor: borderColor,
      );
    }

    final browsing = workProvider.browsingEvent;
    return _buildBrowserVisualView(
      context,
      url:
          browsing?.url ??
          (workProvider.computerEvent?.url.isNotEmpty == true
              ? workProvider.computerEvent!.url
              : 'about:blank'),
      title:
          browsing?.title ??
          (workProvider.computerEvent?.title.isNotEmpty == true
              ? workProvider.computerEvent!.title
              : 'Waiting for browser event'),
      previewHtml: browsing?.snapshot,
      screenshotBase64: browsing?.screenshotBase64.isNotEmpty == true
          ? browsing!.screenshotBase64
          : workProvider.computerEvent?.screenshotBase64,
      isDark: isDark,
      borderColor: borderColor,
    );
  }

  Widget _buildBrowserVisualView(
    BuildContext context, {
    required String url,
    required String title,
    required String? previewHtml,
    String? screenshotBase64,
    required bool isDark,
    required Color borderColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    final addressBg = isDark
        ? const Color(0xFF14171F)
        : const Color(0xFFEFF1F5);

    // Modern browser display url (clean www.domain.com)
    final displayUrl = url
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'/+$'), '');

    final hasDeliverable = previewHtml != null && previewHtml.isNotEmpty;

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
              // Centered URL bar
              Expanded(
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: addressBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Lucide.Lock,
                        size: 11,
                        color: Color(0xFF10B981),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          displayUrl.isNotEmpty ? displayUrl : 'about:blank',
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
            ],
          ),
        ),
        // Browser Webpage Content & Floating "Take control" Button
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Page Body
              if (screenshotBase64 != null && screenshotBase64.isNotEmpty)
                _buildScreenshotPageView(
                  screenshotBase64,
                  isDark,
                  onTap: (position, size) => _handleBrowserTap(position, size),
                  onSwipe: (velocity) => unawaited(
                    _sendBrowserControl(
                      'scroll',
                      direction: velocity < 0 ? 'down' : 'up',
                    ),
                  ),
                )
              else if (hasDeliverable)
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF18181C)
                              : Colors.white,
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
                                        'DELIVERABLE',
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
                                  'Live result',
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
                                  : 'Interactive Deliverable Preview',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: AppFontWeights.bold,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Preview of the result returned by Work.',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Returned deliverable',
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
                  ),
                )
              else
                _buildWaitingForBrowserFrame(context, isDark),

              if (_takeoverEnabled && !hasDeliverable)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 62,
                  child: Material(
                    color: Colors.transparent,
                    child: TextField(
                      controller: _controlTextController,
                      onSubmitted: (value) async {
                        if (value.trim().isEmpty) return;
                        await _sendBrowserControl('insert_text', text: value);
                        _controlTextController.clear();
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF27272A)
                            : Colors.white,
                        hintText: 'Type into the live browser…',
                        prefixIcon: const Icon(Lucide.Keyboard, size: 17),
                        suffixIcon: IconButton(
                          icon: const Icon(Lucide.ChevronRight, size: 18),
                          onPressed: () async {
                            final value = _controlTextController.text;
                            if (value.trim().isEmpty) return;
                            await _sendBrowserControl(
                              'insert_text',
                              text: value,
                            );
                            _controlTextController.clear();
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      Haptics.light();
                      final work = context.read<WorkModeProvider>();
                      if (work.deliverableEvent != null) {
                        WorkDeliverablePreviewModal.show(
                          context,
                          work.deliverableEvent!,
                        );
                      } else {
                        _toggleTakeover();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF27272A).withValues(alpha: 0.95)
                            : Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderColor),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.35 : 0.12,
                            ),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _takeoverEnabled ? Lucide.Keyboard : Lucide.Square,
                            size: 14,
                            color: cs.onSurface,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _takeoverEnabled
                                ? 'Release control'
                                : 'Take control',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: AppFontWeights.semiBold,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWaitingForBrowserFrame(BuildContext context, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Lucide.Monitor, size: 34, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'Waiting for the live browser frame',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: AppFontWeights.semiBold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'The Computer panel will show the real Chromium surface when the backend emits it.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScreenshotPageView(
    String base64Str,
    bool isDark, {
    void Function(Offset position, Size viewportSize)? onTap,
    ValueChanged<double>? onSwipe,
  }) {
    try {
      final decodedImage = base64Decode(base64Str);
      return LayoutBuilder(
        builder: (context, constraints) => ColoredBox(
          color: isDark ? const Color(0xFF14171F) : const Color(0xFFF9FAFB),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: onTap == null
                ? null
                : (details) => onTap(
                    details.localPosition,
                    Size(constraints.maxWidth, constraints.maxHeight),
                  ),
            onVerticalDragEnd: onSwipe == null
                ? null
                : (details) => onSwipe(details.primaryVelocity ?? 0),
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 80),
              child: Center(
                child: Image.memory(
                  decodedImage,
                  width: double.infinity,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
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
    bool isDark = true,
  }) {
    const termBg = Color(0xFF0D1117);
    final cs = Theme.of(context).colorScheme;

    return Container(
      color: termBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Centered Tab Header (matches Image 3)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: termBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: borderColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Lucide.Terminal,
                      size: 12,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'default',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontWeight: AppFontWeights.medium,
                        color: cs.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Terminal Output Stream
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Executed command starting with green ubuntu@sandbox:~$
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.45,
                      ),
                      children: [
                        const TextSpan(
                          text: 'ubuntu@sandbox:~\$ ',
                          style: TextStyle(
                            color: Color(0xFF10B981),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextSpan(
                          text: terminal.command,
                          style: const TextStyle(color: Color(0xFFF0F6FC)),
                        ),
                      ],
                    ),
                  ),
                  if (terminal.output.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      terminal.output,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Color(0xFFC9D1D9),
                        height: 1.45,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  // Cursor prompt
                  Row(
                    children: [
                      const Text(
                        'ubuntu@sandbox:~\$ ',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF10B981),
                        ),
                      ),
                      Container(
                        width: 8,
                        height: 14,
                        color: const Color(0xFF10B981),
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
}
