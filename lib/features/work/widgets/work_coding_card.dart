import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/work/work_agent_event.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';

/// 4. Coding State Card: Real code panel with header, path, syntax/line view, and diff support.
class WorkCodingCard extends StatefulWidget {
  const WorkCodingCard({super.key, required this.codingEvent});

  final WorkCodingEvent codingEvent;

  @override
  State<WorkCodingCard> createState() => _WorkCodingCardState();
}

class _WorkCodingCardState extends State<WorkCodingCard> {
  bool _copied = false;
  bool _expanded = true;

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.codingEvent.newContent));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.codingEvent;
    final isNew = event.isNew || event.diff.isEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF141416), // Dark monochromatic code editor tone
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(25), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(40),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(12),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              border: Border(
                bottom: BorderSide(color: Colors.white.withAlpha(20), width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(Lucide.FileCode, size: 15, color: Color(0xFFD4D4D8)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    event.filePath,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: AppFontWeights.semiBold,
                      color: const Color(0xFFF4F4F5),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isNew
                        ? Colors.white.withAlpha(20)
                        : Colors.white.withAlpha(30),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isNew ? 'NEW' : 'EDIT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: AppFontWeights.bold,
                      letterSpacing: 0.5,
                      color: const Color(0xFFE4E4E7),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  tooltip: _copied ? 'Copied!' : 'Copy Code',
                  icon: Icon(
                    _copied ? Lucide.Check : Lucide.Copy,
                    size: 14,
                    color: const Color(0xFFA1A1AA),
                  ),
                  onPressed: _copyCode,
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  icon: Icon(
                    _expanded ? Lucide.ChevronUp : Lucide.ChevronDown,
                    size: 15,
                    color: const Color(0xFFA1A1AA),
                  ),
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ],
            ),
          ),
          if (_expanded)
            Container(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: isNew
                        ? _buildPlainText(event.newContent)
                        : _buildDiffView(event.diff),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlainText(String code) {
    final lines = code.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(lines.length, (i) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 34,
              child: Text(
                '${i + 1}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFF52525B),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SelectableText(
              lines[i],
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                height: 1.4,
                color: Color(0xFFE4E4E7),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildDiffView(String diff) {
    final lines = diff.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        Color bgColor = Colors.transparent;
        Color textColor = const Color(0xFFE4E4E7);

        if (line.startsWith('+') && !line.startsWith('+++')) {
          bgColor = const Color(0xFF1B382B); // subtle dark green tint
          textColor = const Color(0xFF86EFAC);
        } else if (line.startsWith('-') && !line.startsWith('---')) {
          bgColor = const Color(0xFF381B1B); // subtle dark red tint
          textColor = const Color(0xFFFCA5A5);
        } else if (line.startsWith('@@')) {
          textColor = const Color(0xFF93C5FD);
        }

        return Container(
          color: bgColor,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          child: SelectableText(
            line,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11.5,
              height: 1.4,
              color: textColor,
            ),
          ),
        );
      }).toList(),
    );
  }
}
