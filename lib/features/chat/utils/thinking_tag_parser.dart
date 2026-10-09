import '../../../core/models/message_part.dart';

class ThinkingTagParseResult {
  const ThinkingTagParseResult({
    required this.visibleContent,
    required this.thinkingTexts,
  });

  final String visibleContent;
  final List<String> thinkingTexts;

  bool get hasThinking => thinkingTexts.isNotEmpty;
}

class ThinkingTagHiddenRange {
  const ThinkingTagHiddenRange({
    required this.start,
    required this.end,
    required this.bodyStart,
    required this.bodyEnd,
  });

  /// Inclusive-start, exclusive-end span covering the open tag, body, and
  /// close tag (or the rest of the string when the block is unclosed).
  final int start;
  final int end;

  /// Inclusive-start, exclusive-end span of the think body only.
  final int bodyStart;
  final int bodyEnd;
}

class ThinkingTagParseRanges {
  const ThinkingTagParseRanges({
    required this.visibleContent,
    required this.thinkingTexts,
    required this.hiddenRanges,
  });

  final String visibleContent;
  final List<String> thinkingTexts;

  /// One entry per think block, including empty `<think></think>`.
  final List<ThinkingTagHiddenRange> hiddenRanges;

  bool get hasThinking => thinkingTexts.isNotEmpty || hiddenRanges.isNotEmpty;
}

final _legacyThinkOpenTagRe = RegExp(
  r'<(think|thinking|thought)>|<\|channel>thought',
  caseSensitive: false,
);

final _legacyThinkCloseTagRe = RegExp(
  r'</(think|thinking|thought)>|<channel\|>',
  caseSensitive: false,
);

class ThinkingTagParser {
  /// Test hook: number of [parseLegacyInlineBlocks] executions.
  static int debugParseCount = 0;

  /// Whole-string parse with hidden ranges in input coordinates.
  ///
  /// An unclosed think block at the end is a hidden range plus a thinking
  /// text so export can hide it or render it in the thinking section.
  static ThinkingTagParseRanges parseWithRanges(
    String input, {
    bool includeUnclosed = true,
  }) {
    final visible = StringBuffer();
    final thinkingTexts = <String>[];
    final hiddenRanges = <ThinkingTagHiddenRange>[];
    var cursor = 0;

    while (cursor < input.length) {
      final substring = input.substring(cursor);
      final openMatch = _legacyThinkOpenTagRe.firstMatch(substring);
      final closeMatch = _legacyThinkCloseTagRe.firstMatch(substring);

      // Orphan close tag appearing before any opening tag:
      // text before it is thinking, tag itself is hidden.
      if (closeMatch != null &&
          (openMatch == null || closeMatch.start < openMatch.start)) {
        final closeStart = cursor + closeMatch.start;
        final closeEnd = cursor + closeMatch.end;
        hiddenRanges.add(
          ThinkingTagHiddenRange(
            start: cursor,
            end: closeEnd,
            bodyStart: cursor,
            bodyEnd: closeStart,
          ),
        );
        final thinking = input.substring(cursor, closeStart);
        if (thinking.isNotEmpty) thinkingTexts.add(thinking);
        cursor = closeEnd;
        continue;
      }

      if (openMatch == null) {
        visible.write(substring);
        break;
      }

      final openStart = cursor + openMatch.start;
      final openEnd = cursor + openMatch.end;
      final tagName = openMatch.group(1)?.toLowerCase();
      final closeTag = tagName == null ? '<channel|>' : '</$tagName>';
      final closeStart = input.toLowerCase().indexOf(closeTag, openEnd);
      visible.write(input.substring(cursor, openStart));

      if (closeStart < 0) {
        if (!includeUnclosed) {
          visible.write(input.substring(openStart));
          break;
        }
        hiddenRanges.add(
          ThinkingTagHiddenRange(
            start: openStart,
            end: input.length,
            bodyStart: openEnd,
            bodyEnd: input.length,
          ),
        );
        final thinking = input.substring(openEnd);
        if (thinking.isNotEmpty) thinkingTexts.add(thinking);
        break;
      }

      hiddenRanges.add(
        ThinkingTagHiddenRange(
          start: openStart,
          end: closeStart + closeTag.length,
          bodyStart: openEnd,
          bodyEnd: closeStart,
        ),
      );
      final thinking = input.substring(openEnd, closeStart);
      if (thinking.isNotEmpty) thinkingTexts.add(thinking);
      cursor = closeStart + closeTag.length;
    }

    return ThinkingTagParseRanges(
      visibleContent: visible.toString(),
      thinkingTexts: List.unmodifiable(thinkingTexts),
      hiddenRanges: List.unmodifiable(hiddenRanges),
    );
  }

  /// Walk text spans without moving intervening tools or attachments.
  static void walkSlices(
    List<MessagePart> parts,
    String joined,
    ThinkingTagParseRanges ranges, {
    required void Function(String text) onVisible,
    required void Function(int rangeIndex, String text) onThinking,
    required void Function(MessagePart part) onOther,
  }) {
    var offset = 0;
    var hiddenIndex = 0;
    var pendingRangeIndex = -1;
    final hiddenRanges = ranges.hiddenRanges;
    final pendingThinking = StringBuffer();

    void flushThinking() {
      final thinking = pendingThinking.toString();
      pendingThinking.clear();
      if (thinking.isNotEmpty && pendingRangeIndex >= 0) {
        onThinking(pendingRangeIndex, thinking);
      }
      pendingRangeIndex = -1;
    }

    for (final part in parts) {
      if (part is! TextPart) {
        flushThinking();
        onOther(part);
        continue;
      }
      final start = offset;
      final end = offset + part.text.length;
      var cursor = start;
      while (cursor < end) {
        if (hiddenIndex < hiddenRanges.length &&
            hiddenRanges[hiddenIndex].start <= cursor &&
            cursor < hiddenRanges[hiddenIndex].end) {
          final range = hiddenRanges[hiddenIndex];
          final sliceStart = cursor < range.bodyStart
              ? range.bodyStart
              : cursor;
          final sliceEnd = range.bodyEnd < end ? range.bodyEnd : end;
          if (sliceEnd > sliceStart) {
            pendingRangeIndex = hiddenIndex;
            pendingThinking.write(joined.substring(sliceStart, sliceEnd));
          }
          cursor = range.end < end ? range.end : end;
          if (cursor >= range.end) {
            hiddenIndex++;
            flushThinking();
          }
          continue;
        }
        final visibleEnd = hiddenIndex < hiddenRanges.length
            ? hiddenRanges[hiddenIndex].start
            : end;
        final sliceEnd = visibleEnd < end ? visibleEnd : end;
        if (sliceEnd > cursor) {
          flushThinking();
          onVisible(joined.substring(cursor, sliceEnd));
        }
        cursor = sliceEnd;
      }
      offset = end;
    }
    flushThinking();
  }

  /// Visible characters of `[start, end)` after subtracting [hiddenRanges].
  static String visibleSlice(
    String input, {
    required int start,
    required int end,
    required List<ThinkingTagHiddenRange> hiddenRanges,
  }) {
    if (start >= end) return '';
    if (hiddenRanges.isEmpty) return input.substring(start, end);
    final out = StringBuffer();
    var cursor = start;
    for (final range in hiddenRanges) {
      if (range.end <= cursor) continue;
      if (range.start >= end) break;
      if (range.start > cursor) {
        out.write(input.substring(cursor, range.start.clamp(cursor, end)));
      }
      if (range.end > cursor) {
        cursor = range.end < end ? range.end : end;
      }
    }
    if (cursor < end) out.write(input.substring(cursor, end));
    return out.toString();
  }

  static ThinkingTagParseResult parseLegacyInlineBlocks(String input) {
    debugParseCount++;
    final visible = StringBuffer();
    final thinkingTexts = <String>[];
    var cursor = 0;

    while (cursor < input.length) {
      final substring = input.substring(cursor);
      final openMatch = _legacyThinkOpenTagRe.firstMatch(substring);
      final closeMatch = _legacyThinkCloseTagRe.firstMatch(substring);

      // Orphan close tag appearing before any opening tag:
      // text before it is thinking, visible continues after it.
      if (closeMatch != null &&
          (openMatch == null || closeMatch.start < openMatch.start)) {
        final closeStart = cursor + closeMatch.start;
        final closeEnd = cursor + closeMatch.end;
        final thinking = input.substring(cursor, closeStart).trim();
        if (thinking.isNotEmpty) {
          thinkingTexts.add(thinking);
        }
        cursor = closeEnd;
        continue;
      }

      if (openMatch == null) {
        visible.write(substring);
        break;
      }

      final openStart = cursor + openMatch.start;
      final openEnd = cursor + openMatch.end;
      final tagName = openMatch.group(1)?.toLowerCase();
      final closeTag = tagName == null ? '<channel|>' : '</$tagName>';
      final closeStart = input.toLowerCase().indexOf(closeTag, openEnd);

      if (closeStart == -1) {
        visible.write(input.substring(cursor));
        break;
      }

      visible.write(input.substring(cursor, openStart));
      final thinking = input.substring(openEnd, closeStart).trim();
      if (thinking.isNotEmpty) {
        thinkingTexts.add(thinking);
      }
      cursor = closeStart + closeTag.length;
    }

    return ThinkingTagParseResult(
      visibleContent: visible.toString().trim(),
      thinkingTexts: List.unmodifiable(thinkingTexts),
    );
  }

  /// Strip all thinking blocks and tags, returning only the clean visible content.
  static String stripReasoning(String input) {
    if (input.isEmpty) return '';
    final parsed = parseWithRanges(input, includeUnclosed: true);
    return parsed.visibleContent.trim();
  }

  /// Cleans a conversation title to ensure it never leaks reasoning, thinking tags,
  /// or raw conversation prefixes like "User: ...".
  static String cleanConversationTitle(String input) {
    if (input.isEmpty) return 'New Chat';
    
    // 1. Strip reasoning blocks/tags
    var cleaned = stripReasoning(input);
    if (cleaned.isEmpty) cleaned = input;

    // 2. Strip orphan close/open tags
    cleaned = cleaned
        .replaceAll(RegExp(r'</?(?:think|thinking|thought)>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<\|channel>(?:thought)?|<channel\|>', caseSensitive: false), '')
        .trim();

    // 3. Remove leading markdown formatting (#, *, `, _)
    cleaned = cleaned.replaceAll(RegExp(r'^[#*`_\s]+|[#*`_\s]+$'), '').trim();

    // 4. Strip surrounding quotes
    cleaned = cleaned.replaceAll(RegExp(r'^["' "'" r'«“‘]+|["' "'" r'»”’]+$'), '').trim();

    // 5. Remove known prefixes like "User:", "Assistant:", "Title:", "Topic:", "Subject:"
    final prefixRe = RegExp(
      r'^(?:user|assistant|title|topic|subject|عنوان|الموضوع)\s*:\s*',
      caseSensitive: false,
    );
    while (prefixRe.hasMatch(cleaned)) {
      cleaned = cleaned.replaceFirst(prefixRe, '').trim();
    }

    // 6. Detect and clean leaked reasoning sentences like "The user is asking me to..."
    final leakedReasoningPatterns = [
      RegExp(r'^(?:the\s+user\s+is\s+asking\s+(?:me\s+)?(?:to\s+|for\s+)?)(.*)', caseSensitive: false),
      RegExp(r'^(?:the\s+user\s+wants\s+(?:me\s+)?(?:to\s+)?)(.*)', caseSensitive: false),
      RegExp(r'^(?:the\s+user\s+asked\s+(?:me\s+)?(?:to\s+)?)(.*)', caseSensitive: false),
      RegExp(r'^(?:i\s+need\s+to\s+(?:summarize|create|give)\s+(?:a\s+title\s+for\s+)?)(.*)', caseSensitive: false),
      RegExp(r'^(?:here\s+is\s+a\s+(?:short\s+)?title\s*:\s*)(.*)', caseSensitive: false),
      RegExp(r'^(?:based\s+on\s+the\s+conversation\s*,?\s*)(.*)', caseSensitive: false),
      RegExp(r'^(?:المستخدم\s+(?:يطلب|يريد|يسأل)\s+(?:عن\s+|أن\s+)?)(.*)', caseSensitive: false),
    ];

    for (final pat in leakedReasoningPatterns) {
      final match = pat.firstMatch(cleaned);
      if (match != null && match.groupCount >= 1) {
        final remainder = match.group(1)?.trim() ?? '';
        if (remainder.isNotEmpty) {
          cleaned = remainder;
          // Capitalize first letter of remainder if English
          if (cleaned.isNotEmpty && RegExp(r'^[a-z]').hasMatch(cleaned)) {
            cleaned = cleaned[0].toUpperCase() + cleaned.substring(1);
          }
        }
        break;
      }
    }

    // Strip again after pattern extraction
    cleaned = cleaned.replaceAll(RegExp(r'^["' "'" r'«“‘]+|["' "'" r'»”’]+$'), '').trim();

    // 7. Collapse newlines and multi-spaces
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (cleaned.isEmpty || cleaned == '...' || cleaned == '..') {
      return 'New Chat';
    }

    if (cleaned.length > 36) {
      cleaned = '${cleaned.substring(0, 36).trim()}...';
    }

    return cleaned;
  }
}
