import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';

class ReasoningBudgetCustomDialog {
  static Future<int?> show(
    BuildContext context, {
    required int initialValue,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: initialValue.toString());

    int? parseValue() => int.tryParse(controller.text.trim());
    bool isValid(int? v) => v != null && (v == -1 || v >= 0);

    try {
      return await showDialog<int>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setLocal) {
              final parsed = parseValue();
              final valid = isValid(parsed);
              void submit() {
                if (!valid || parsed == null) return;
                Navigator.of(ctx).pop(parsed);
              }

              final theme = Theme.of(ctx);
              final cs = theme.colorScheme;
              final isDark = theme.brightness == Brightness.dark;

              return AlertDialog(
                backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: cs.outline.withValues(alpha: isDark ? 0.25 : 0.12),
                    width: 0.8,
                  ),
                ),
                titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                actionsPadding: const EdgeInsets.fromLTRB(16, 16, 20, 16),
                title: Text(
                  l10n.reasoningBudgetSheetCustomLabel,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                content: SizedBox(
                  width: 360,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: controller,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^-?\d*$')),
                        ],
                        style: TextStyle(
                          fontSize: 16,
                          color: cs.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: cs.surfaceContainerHighest.withValues(
                            alpha: isDark ? 0.35 : 0.45,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: cs.outline.withValues(alpha: 0.15),
                              width: 0.8,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: cs.onSurface.withValues(alpha: 0.6),
                              width: 1.2,
                            ),
                          ),
                        ),
                        onChanged: (_) => setLocal(() {}),
                        onSubmitted: (_) => submit(),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.reasoningBudgetSheetCustomHint,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: cs.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(l10n.assistantEditEmojiDialogCancel),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: valid ? submit : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: isDark ? Colors.white : Colors.black,
                      foregroundColor: isDark ? Colors.black : Colors.white,
                      disabledBackgroundColor: isDark
                          ? const Color(0xFF2C2C2E)
                          : const Color(0xFFE5E7EB),
                      disabledForegroundColor: isDark
                          ? const Color(0xFF6B7280)
                          : const Color(0xFF9CA3AF),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(l10n.assistantEditEmojiDialogSave),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    }
  }
}
