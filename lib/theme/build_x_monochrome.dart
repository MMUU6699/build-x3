import 'package:flutter/material.dart';

/// Enforces the app's grayscale palette, including widgets with local colors.
class BuildXMonochrome extends StatelessWidget {
  const BuildXMonochrome({super.key, required this.child});

  final Widget child;

  static const _filter = ColorFilter.matrix(<double>[
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);

  @override
  Widget build(BuildContext context) =>
      ColorFiltered(colorFilter: _filter, child: child);
}
