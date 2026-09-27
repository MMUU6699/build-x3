import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/work_mode_provider.dart';
import '../../../core/work_mode_config.dart';
import '../../../core/services/haptics.dart';
import '../../../theme/app_font_weights.dart';
import '../../../theme/header_tokens.dart';

class ModeSegmentedToggle extends StatelessWidget {
  const ModeSegmentedToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final workProvider = context.watch<WorkModeProvider>();
    final isWork = workProvider.isWorkMode;

    final trackBg = Colors.white;
    final trackBorder = Colors.black.withValues(alpha: 0.06);

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppHeaderTokens.toggleRadius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            height: AppHeaderTokens.toggleHeight,
            padding: const EdgeInsets.all(3.0),
            decoration: BoxDecoration(
              color: trackBg,
              borderRadius: BorderRadius.circular(AppHeaderTokens.toggleRadius),
              border: Border.all(color: trackBorder, width: 0.8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
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
                    if (isWork) {
                      Haptics.light();
                      workProvider.setMode(AppWorkMode.chat);
                    }
                  },
                ),
                _buildSegment(
                  context,
                  label: 'Work',
                  selected: isWork,
                  onTap: () {
                    if (!isWork) {
                      Haptics.light();
                      workProvider.setMode(AppWorkMode.work);
                    }
                  },
                ),
              ],
            ),
          ),
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
    final selectedBg = const Color(0xFFF4F4F5);
    final selectedBorder = Colors.black.withValues(alpha: 0.04);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOutCubic,
        height: AppHeaderTokens.selectedPillHeight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: selected ? selectedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(
            AppHeaderTokens.selectedPillRadius,
          ),
          border: selected
              ? Border.all(color: selectedBorder, width: 0.8)
              : null,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: selected
                ? AppFontWeights.semibold
                : AppFontWeights.medium,
            color: selected ? const Color(0xFF09090B) : const Color(0xFF71717A),
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }
}
