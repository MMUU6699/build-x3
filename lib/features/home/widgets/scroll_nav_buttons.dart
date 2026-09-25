import 'package:flutter/material.dart';

const scrollNavHoverRegionKey = ValueKey('scroll-nav-hover-region');

/// Glassy scroll navigation buttons panel - disabled in Build X.
class ScrollNavButtonsPanel extends StatelessWidget {
  const ScrollNavButtonsPanel({
    super.key,
    required this.visible,
    required this.onScrollToTop,
    required this.onPreviousMessage,
    required this.onNextMessage,
    required this.onScrollToBottom,
    this.bottomOffset = 80,
    this.iconSize = 16,
    this.buttonPadding = 6,
    this.buttonSpacing = 8,
    this.hoverEnabled = false,
    this.onHoverChanged,
  });

  final bool visible;
  final bool hoverEnabled;
  final ValueChanged<bool>? onHoverChanged;
  final VoidCallback onScrollToTop;
  final VoidCallback onPreviousMessage;
  final VoidCallback onNextMessage;
  final VoidCallback onScrollToBottom;
  final double bottomOffset;
  final double iconSize;
  final double buttonPadding;
  final double buttonSpacing;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
