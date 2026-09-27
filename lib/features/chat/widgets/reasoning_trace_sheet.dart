import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/markdown_with_highlight.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';

import '../../../icons/reasoning_icons.dart';

class ReasoningTraceSheet extends StatelessWidget {
  const ReasoningTraceSheet({
    super.key,
    required this.text,
    required this.loading,
  });

  final String text;
  final bool loading;

  static Future<void> show(
    BuildContext context, {
    required String text,
    required bool loading,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (_) => ReasoningTraceSheet(text: text, loading: loading),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    
    final l10n = AppLocalizations.of(context)!;
    final enableReasoningMarkdown = context.select<SettingsProvider, bool>(
      (s) => s.enableReasoningMarkdown,
    );
    

    final display = text.replaceAll('\r', '').trim();
    final baseStyle = DefaultTextStyle.of(
      context,
    ).style.copyWith(fontSize: 14.0, height: 1.45, color: cs.onSurface);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    ReasoningIcons.thinkingCardIcon(size: 20, color: cs.primary),
                    const SizedBox(width: 10),
                    Text(
                      l10n.chatMessageWidgetDeepThinking,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: AppFontWeights.semibold,
                        color: cs.onSurface,
                      ),
                    ),
                    const Spacer(),
                    if (loading)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(cs.primary),
                          ),
                        ),
                      ),
                    IosIconButton(
                      icon: Lucide.X,
                      size: 22,
                      minSize: 44,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // Body
              Expanded(
                child: SelectionArea(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    child: enableReasoningMarkdown
                        ? MarkdownWithCodeHighlight(
                            text: display.isNotEmpty ? display : 'â€¦',
                            baseStyle: baseStyle,
                            streaming: loading,
                          )
                        : Text(
                            display.isNotEmpty ? display : 'â€¦',
                            style: baseStyle,
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
