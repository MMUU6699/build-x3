enum ThinkTagChunkType {
  reasoningStart,
  reasoningDelta,
  reasoningEnd,
  textDelta,
}

class ThinkTagChunk {
  const ThinkTagChunk.reasoningStart()
    : type = ThinkTagChunkType.reasoningStart,
      text = '';

  const ThinkTagChunk.reasoning(this.text)
    : type = ThinkTagChunkType.reasoningDelta;

  const ThinkTagChunk.reasoningEnd()
    : type = ThinkTagChunkType.reasoningEnd,
      text = '';

  const ThinkTagChunk.text(this.text) : type = ThinkTagChunkType.textDelta;

  final ThinkTagChunkType type;
  final String text;

  @override
  String toString() => 'ThinkTagChunk($type, text: $text)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThinkTagChunk &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          text == other.text;

  @override
  int get hashCode => Object.hash(type, text);
}

/// A streaming filter that intercepts thinking tags (`<think>...</think>`,
/// `<thinking>...</thinking>`, `<thought>...</thought>`, `<|channel>thought...<channel|>`)
/// and orphan `</think>` tags across chunk boundaries.
///
/// Ensures raw reasoning text and think tags never leak into visible text deltas.
class ThinkTagStreamFilter {
  ThinkTagStreamFilter({
    this.suppressReasoning = false,
    this.assumedThinking = false,
  }) : _inThinking = assumedThinking;

  final bool suppressReasoning;
  final bool assumedThinking;

  bool _inThinking;
  bool _emittedReasoningStart = false;
  bool _emittedReasoningEnd = false;
  bool _everSeenThinkTag = false;

  final StringBuffer _tagBuffer = StringBuffer();
  final StringBuffer _assumedBuffer = StringBuffer();

  static final RegExp _openTagRe = RegExp(
    r'^(?:<(think|thinking|thought)>|<\|channel>thought\n?)',
    caseSensitive: false,
  );

  static final RegExp _closeTagRe = RegExp(
    r'^(?:</(think|thinking|thought)>|<channel\|>\n?)',
    caseSensitive: false,
  );

  /// Candidate prefix patterns for tags that might be split across chunks.
  static final List<String> _candidatePrefixes = [
    '<',
    '<t',
    '<th',
    '<thi',
    '<thin',
    '<think',
    '<thinki',
    '<thinkin',
    '<thinking',
    '<thou',
    '<thoug',
    '<though',
    '<thought',
    '</',
    '</t',
    '</th',
    '</thi',
    '</thin',
    '</think',
    '</thinki',
    '</thinkin',
    '</thinking',
    '</thou',
    '</thoug',
    '</though',
    '</thought',
    '<|',
    '<|c',
    '<|ch',
    '<|cha',
    '<|chan',
    '<|chann',
    '<|channe',
    '<|channel',
    '<|channel>',
    '<|channel>t',
    '<|channel>th',
    '<|channel>tho',
    '<|channel>thou',
    '<|channel>thoug',
    '<|channel>though',
    '<|channel>thought',
    '<c',
    '<ch',
    '<cha',
    '<chan',
    '<chann',
    '<channe',
    '<channel',
    '<channel|',
  ];

  static bool _couldBeTagPrefix(String s) {
    if (s.isEmpty) return false;
    final lower = s.toLowerCase();
    for (final prefix in _candidatePrefixes) {
      if (prefix == lower) return true;
      if (prefix.startsWith(lower)) return true;
    }
    return false;
  }

  /// Process an incoming chunk string and return filtered chunks.
  List<ThinkTagChunk> feed(String chunk) {
    if (chunk.isEmpty) return const [];
    final results = <ThinkTagChunk>[];

    // Prepend any leftover partial tag from previous chunk
    String text;
    if (_tagBuffer.isNotEmpty) {
      text = _tagBuffer.toString() + chunk;
      _tagBuffer.clear();
    } else {
      text = chunk;
    }

    var cursor = 0;
    while (cursor < text.length) {
      // 1. Check if we're at a potential tag start
      final remaining = text.substring(cursor);

      // Check open tag
      final openMatch = _openTagRe.firstMatch(remaining);
      if (openMatch != null && openMatch.start == 0) {
        _everSeenThinkTag = true;
        cursor += openMatch.end;
        if (!_inThinking) {
          _inThinking = true;
          if (!suppressReasoning && !_emittedReasoningStart) {
            _emittedReasoningStart = true;
            results.add(const ThinkTagChunk.reasoningStart());
          }
        }
        continue;
      }

      // Check close tag
      final closeMatch = _closeTagRe.firstMatch(remaining);
      if (closeMatch != null && closeMatch.start == 0) {
        _everSeenThinkTag = true;
        cursor += closeMatch.end;

        // Skip leading whitespace / newlines after </think> tag
        while (cursor < text.length &&
            (text[cursor] == '\n' || text[cursor] == '\r')) {
          cursor++;
        }

        if (_inThinking) {
          _inThinking = false;
          // Discard any assumed thinking buffer
          _assumedBuffer.clear();
          if (!suppressReasoning) {
            results.add(const ThinkTagChunk.reasoningEnd());
            _emittedReasoningEnd = true;
          }
        }
        continue;
      }

      // Find the next '<' character
      final nextLt = remaining.indexOf('<');
      if (nextLt == -1) {
        // No tag start anywhere in remaining string
        _processTextSegment(remaining, results);
        cursor = text.length;
        break;
      } else if (nextLt > 0) {
        // Text before '<'
        final segment = remaining.substring(0, nextLt);
        _processTextSegment(segment, results);
        cursor += nextLt;
        continue;
      }

      // nextLt == 0: remaining starts with '<'.
      // Check if the entire remainder could be a partial tag at chunk end.
      if (_couldBeTagPrefix(remaining)) {
        // Buffer this prefix for the next chunk
        _tagBuffer.write(remaining);
        cursor = text.length;
        break;
      } else {
        // Not a tag prefix, just a regular '<' or false alarm tag
        _processTextSegment(remaining.substring(0, 1), results);
        cursor += 1;
      }
    }

    return results;
  }

  void _processTextSegment(String segment, List<ThinkTagChunk> results) {
    if (segment.isEmpty) return;

    if (_inThinking) {
      if (suppressReasoning) {
        if (assumedThinking && !_everSeenThinkTag) {
          // If in assumed thinking mode before seeing </think>, buffer it
          // in case </think> never arrives (meaning it was actually visible answer).
          _assumedBuffer.write(segment);
        }
        // When suppressReasoning is true and in thinking, do not yield reasoning
      } else {
        if (!_emittedReasoningStart) {
          _emittedReasoningStart = true;
          results.add(const ThinkTagChunk.reasoningStart());
        }
        results.add(ThinkTagChunk.reasoning(segment));
      }
    } else {
      results.add(ThinkTagChunk.text(segment));
    }
  }

  /// Finalize the stream and flush any remaining buffers.
  List<ThinkTagChunk> flush() {
    final results = <ThinkTagChunk>[];

    // If tag buffer had something that was not a complete tag, output it
    if (_tagBuffer.isNotEmpty) {
      final leftover = _tagBuffer.toString();
      _tagBuffer.clear();
      _processTextSegment(leftover, results);
    }

    // If assumed thinking was active but no </think> was ever seen,
    // the assumed text was actually the plain answer!
    if (assumedThinking && !_everSeenThinkTag && _assumedBuffer.isNotEmpty) {
      final saved = _assumedBuffer.toString();
      _assumedBuffer.clear();
      results.add(ThinkTagChunk.text(saved));
    }

    if (_inThinking && !suppressReasoning && !_emittedReasoningEnd) {
      results.add(const ThinkTagChunk.reasoningEnd());
      _emittedReasoningEnd = true;
    }

    return results;
  }
}
