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
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bg = isDark
        ? cs.surface.withValues(alpha: 0.90)
        : cs.surface.withValues(alpha: 0.98);
    final border = isDark
        ? cs.outline.withValues(alpha: 0.20)
        : cs.outline.withValues(alpha: 0.12);

    return Center(
      child: Container(
        height: 42,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(21),
          border: Border.all(color: border, width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
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
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final selectedBg = isDark
        ? cs.onSurface.withValues(alpha: 0.14)
        : cs.onSurface.withValues(alpha: 0.08);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? selectedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: selected
                ? AppFontWeights.semibold
                : AppFontWeights.regular,
            color: selected
                ? cs.onSurface
                : cs.onSurfaceVariant.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }
}
