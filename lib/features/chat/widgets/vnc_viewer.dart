import 'dart:convert';

import 'package:flutter/material.dart';

/// Displays a real screenshot captured from Daytona Computer Use.
/// Daytona VNC access is proxied by its authenticated dashboard; the app must
/// not guess or construct a public VNC URL from a sandbox identifier.
class VncViewer extends StatelessWidget {
  const VncViewer({super.key, this.screenshotBase64 = '', this.enabled = true});

  final String screenshotBase64;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    if (screenshotBase64.isEmpty) {
      return const Center(
        child: Text(
          'Waiting for live Daytona computer activity…',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    try {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Image.memory(
            base64Decode(screenshotBase64),
            fit: BoxFit.contain,
            gaplessPlayback: true,
          ),
        ),
      );
    } on FormatException {
      return const Center(
        child: Text('The latest Daytona screenshot could not be displayed.'),
      );
    }
  }
}
