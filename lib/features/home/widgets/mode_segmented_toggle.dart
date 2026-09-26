import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/work_mode_provider.dart';
import '../../../core/work_mode_config.dart';
import '../../../core/services/haptics.dart';
import '../../../theme/app_font_weights.dart';

/// Redesigned Segmented pill toggle [ Chat | Work ] matching Build X header styling.
///
/// Shares the 44px height, corner radius (22px), border weight, and shadow of
/// HeaderBubbleButton so the header controls read as one cohesive unit.
class ModeSegmentedToggle extends StatelessWidget {
  const ModeSegmentedToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final workProvider = context.watch<WorkModeProvider>();
    final isWork = workProvider.isWorkMode;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final trackBg = isDark
        ? const Color(0xFF18181B)
        : const Color(0xFFE4E4E7);
    final trackBorder = isDark
        ? const Color(0xFF27272A)
        : const Color(0xFFD4D4D8);

    return Center(
      child: Container(
        height: 40,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: trackBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: trackBorder, width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
              blurRadius: 6,
              offset: const Offset(0, 1.5),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSegment(
              context,
              label: 'Chat',
              selected: !isWork,
              onTap: () {
                Haptics.light();
                workProvider.setMode(AppWorkMode.chat);
              },
            ),
            _buildSegment(
              context,
              label: 'Work',
              selected: isWork,
              onTap: () {
                Haptics.light();
                workProvider.setMode(AppWorkMode.work);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegment(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final selectedBg = isDark
        ? const Color(0xFF27272A)
        : Colors.white;
    final selectedBorder = isDark
        ? const Color(0xFF3F3F46)
        : const Color(0xFFD4D4D8);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? selectedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
          border: selected
              ? Border.all(color: selectedBorder, width: 0.8)
              : null,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: selected
                ? AppFontWeights.semibold
                : AppFontWeights.medium,
            color: selected
                ? (isDark ? Colors.white : Colors.black)
                : (isDark
                    ? const Color(0xFFA1A1AA)
                    : const Color(0xFF71717A)),
          ),
        ),
      ),
    );
  }
}
