import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/assistant.dart';
import '../../../core/models/skills_binding.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/haptics.dart';
import '../../../core/services/skills/skills_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../model/widgets/ocr_prompt_sheet.dart';
import '../../workspace/pages/skills_page.dart';
import '../../workspace/widgets/skills/conversation_skills_sheet.dart';
import '../utils/ensure_conversation.dart';
import '../../../theme/app_font_weights.dart';
import 'tools_sheet_row.dart';
import 'reasoning_budget_sheet.dart';

/// Row that opens the session skills picker, and pushes the skills library on
/// a long press.
const Key sessionSkillsKey = ValueKey<String>('bottom-tools-session-skills');

class BottomToolsSheet extends StatelessWidget {
  const BottomToolsSheet({
    super.key,
    this.onCamera,
    this.onPhotos,
    this.onUpload,
    this.onClear,
    this.clearLabel,
    this.assistantId,
    this.conversationId,
    this.onClose,
    this.webSearchActive = false,
    this.onToggleWebSearch,
    this.onConfigureSearch,
  });

  final VoidCallback? onCamera;
  final VoidCallback? onPhotos;
  final VoidCallback? onUpload;
  final VoidCallback? onClear;
  final String? clearLabel;
  final String? assistantId;
  final String? conversationId;
  final VoidCallback? onClose;
  final bool webSearchActive;
  final VoidCallback? onToggleWebSearch;
  final VoidCallback? onConfigureSearch;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;

    Widget roundedAction({
      required IconData icon,
      required String label,
      VoidCallback? onTap,
    }) {
      final cardColor = isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.04);
      return Expanded(
        child: SizedBox(
          height: 72,
          child: IosCardPress(
            baseColor: cardColor,
            borderRadius: BorderRadius.circular(16),
            pressedScale: 0.98,
            duration: const Duration(milliseconds: 260),
            onTap: () {
              Haptics.light();
              onTap?.call();
            },
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 24,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1C1C20).withValues(alpha: 0.82)
                      : Colors.white.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.07),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.35 : 0.10,
                      ),
                      blurRadius: 28,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag handle
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                roundedAction(
                                  icon: Lucide.Camera,
                                  label: l10n.bottomToolsSheetCamera,
                                  onTap: onCamera,
                                ),
                                const SizedBox(width: 12),
                                roundedAction(
                                  icon: Lucide.Image,
                                  label: l10n.bottomToolsSheetPhotos,
                                  onTap: onPhotos,
                                ),
                                const SizedBox(width: 12),
                                roundedAction(
                                  icon: Lucide.Paperclip,
                                  label: l10n.bottomToolsSheetUpload,
                                  onTap: onUpload,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 4, bottom: 6),
                                child: Text(
                                  'Tools & Capabilities',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: AppFontWeights.semibold,
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                            ),
                            ToolsSheetRow(
                              icon: Lucide.Globe,
                              label: 'Search the Web',
                              subtitle: 'Find real-time answers and sources online',
                              selected: webSearchActive,
                              onTap: () {
                                Haptics.light();
                                Navigator.of(context).maybePop();
                                onToggleWebSearch?.call();
                              },
                              onLongPress: onConfigureSearch != null
                                  ? () {
                                      Haptics.light();
                                      Navigator.of(context).maybePop();
                                      onConfigureSearch?.call();
                                    }
                                  : null,
                            ),
                            const SizedBox(height: 8),
                            Builder(
                              builder: (ctx) {
                                final sp = ctx.watch<SettingsProvider>();
                                final isThinkingActive =
                                    sp.thinkingBudget != null && sp.thinkingBudget != 0;
                                final b = sp.thinkingBudget;
                                final String subtitle;
                                if (!isThinkingActive) {
                                  subtitle = 'Reason thoroughly before answering';
                                } else if (b == null || b == -1) {
                                  subtitle = 'Auto reasoning level';
                                } else if (b <= 1024) {
                                  subtitle = 'Low reasoning effort';
                                } else if (b <= 4096) {
                                  subtitle = 'Medium reasoning effort';
                                } else if (b <= 16384) {
                                  subtitle = 'High reasoning effort';
                                } else {
                                  subtitle = 'Custom budget (${(b / 1024).round()}k tokens)';
                                }

                                return ToolsSheetRow(
                                  icon: Lucide.Brain,
                                  label: 'Thinking mode',
                                  subtitle: subtitle,
                                  selected: isThinkingActive,
                                  onTap: () async {
                                    Haptics.light();
                                    final ap = context.read<AssistantProvider>();
                                    Navigator.of(context).maybePop();
                                    final newBudget = isThinkingActive ? 0 : 4096;
                                    await sp.setThinkingBudget(newBudget);
                                    final a = ap.currentAssistant;
                                    if (a != null) {
                                      await ap.updateAssistant(a.copyWith(thinkingBudget: newBudget));
                                    }
                                  },
                                  onLongPress: () async {
                                    Haptics.light();
                                    Navigator.of(context).maybePop();
                                    await showReasoningBudgetSheet(context);
                                  },
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            _LearningAndClearSection(
                              clearLabel: clearLabel,
                              onClear: onClear,
                              assistantId: assistantId,
                              conversationId: conversationId,
                              onClose: onClose,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LearningAndClearSection extends StatefulWidget {
  const _LearningAndClearSection({
    this.onClear,
    this.clearLabel,
    this.assistantId,
    this.conversationId,
    this.onClose,
  });
  final VoidCallback? onClear;
  final String? clearLabel;
  final String? assistantId;
  final String? conversationId;
  final VoidCallback? onClose;

  @override
  State<_LearningAndClearSection> createState() =>
      _LearningAndClearSectionState();
}

class _LearningAndClearSectionState extends State<_LearningAndClearSection> {
  String? _promptConversationId;

  @override
  void initState() {
    super.initState();
  }

  Assistant? _assistant({bool listen = false}) {
    try {
      final provider = Provider.of<AssistantProvider>(context, listen: listen);
      final id = widget.assistantId;
      if (id != null) return provider.getById(id);
      return provider.currentAssistant;
    } catch (_) {
      return null;
    }
  }

  Future<void> _openSessionSkills() async {
    Haptics.light();
    final id = await ensureConversationId(
      context,
      conversationId: _promptConversationId ?? widget.conversationId,
      assistantId: widget.assistantId,
    );
    if (id == null || !mounted) return;
    _promptConversationId = id;
    await showConversationSkillsSheet(
      context,
      conversationId: id,
      assistant: _assistant(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final skills = context.watch<SkillsService>();
    final chat = context.watch<ChatService>();
    final assistant = _assistant(listen: true);
    final hasOcrModel =
        settings.ocrModelProvider != null && settings.ocrModelId != null;
    final scopeId = _promptConversationId ?? widget.conversationId;
    final skillBinding = SkillsBinding.fromExtras(
      scopeId == null
          ? const {}
          : chat.getConversation(scopeId)?.extras ?? const {},
    );
    final enabledSkillCount = skills
        .resolveForAssistant(
          assistant,
          conversationOverride: skillBinding.skillIds,
        )
        .length;
    final chevron = ToolsSheetRow.chevron(context);
    Widget selectionTrailing(int enabled, int total) => enabled == 0
        ? chevron
        : Text(
            '$enabled/$total',
            style: TextStyle(
              fontSize: 13,
              fontWeight: AppFontWeights.medium,
              color: Theme.of(context).colorScheme.primary,
            ),
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ToolsSheetRow(
          key: sessionSkillsKey,
          icon: Lucide.WandSparkles,
          label: l10n.workspaceEntrySessionSkills,
          onTap: () => unawaited(_openSessionSkills()),
          onLongPress: () {
            Haptics.light();
            final rootNav = Navigator.of(context, rootNavigator: true);
            Navigator.of(context).maybePop();
            Future.microtask(() {
              if (!rootNav.mounted) return;
              unawaited(openSkillsPage(rootNav.context));
            });
          },
          trailing: selectionTrailing(enabledSkillCount, skills.skills.length),
        ),

        if (hasOcrModel) ...[
          const SizedBox(height: 8),
          ToolsSheetRow(
            icon: Lucide.Eye,
            label: l10n.bottomToolsSheetOcr,
            selected: settings.ocrEnabled,
            onTap: () async {
              Haptics.light();
              final sp = context.read<SettingsProvider>();
              await sp.setOcrEnabled(!sp.ocrEnabled);
              if (!context.mounted) return;
              Navigator.of(context).maybePop();
            },
            onLongPress: () => showOcrPromptSheet(context),
          ),
        ],
        const SizedBox(height: 8),
        ToolsSheetRow(
          icon: Lucide.workflow,
          label: l10n.contextManagement,
          onTap: () {
            Haptics.light();
            widget.onClear?.call();
          },
          trailing: chevron,
        ),
      ],
    );
  }
}
