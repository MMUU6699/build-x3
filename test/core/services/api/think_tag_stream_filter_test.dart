import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/api/stream/think_tag_stream_filter.dart';

void main() {
  group('ThinkTagStreamFilter - Explicit tags', () {
    test('extracts <think>...</think> with suppressReasoning: true', () {
      final filter = ThinkTagStreamFilter(suppressReasoning: true);
      final chunks = <ThinkTagChunk>[];

      chunks.addAll(
        filter.feed('<think>Internal reasoning</think>Hello world!'),
      );
      chunks.addAll(filter.flush());

      expect(chunks, [const ThinkTagChunk.text('Hello world!')]);
    });

    test('extracts <think>...</think> with suppressReasoning: false', () {
      final filter = ThinkTagStreamFilter(suppressReasoning: false);
      final chunks = <ThinkTagChunk>[];

      chunks.addAll(
        filter.feed('<think>Internal reasoning</think>Hello world!'),
      );
      chunks.addAll(filter.flush());

      expect(chunks, [
        const ThinkTagChunk.reasoningStart(),
        const ThinkTagChunk.reasoning('Internal reasoning'),
        const ThinkTagChunk.reasoningEnd(),
        const ThinkTagChunk.text('Hello world!'),
      ]);
    });

    test('handles tags split across chunks', () {
      final filter = ThinkTagStreamFilter(suppressReasoning: false);
      final chunks = <ThinkTagChunk>[];

      chunks.addAll(filter.feed('<th'));
      chunks.addAll(filter.feed('ink>Step 1'));
      chunks.addAll(filter.feed(' Step 2</th'));
      chunks.addAll(filter.feed('ink>Result'));
      chunks.addAll(filter.flush());

      expect(chunks, [
        const ThinkTagChunk.reasoningStart(),
        const ThinkTagChunk.reasoning('Step 1'),
        const ThinkTagChunk.reasoning(' Step 2'),
        const ThinkTagChunk.reasoningEnd(),
        const ThinkTagChunk.text('Result'),
      ]);
    });

    test('handles false alarm tag', () {
      final filter = ThinkTagStreamFilter(suppressReasoning: false);
      final chunks = <ThinkTagChunk>[];

      chunks.addAll(filter.feed('if (x <'));
      chunks.addAll(filter.feed(' 5) return;'));
      chunks.addAll(filter.flush());

      expect(chunks, [
        const ThinkTagChunk.text('if (x '),
        const ThinkTagChunk.text('<'),
        const ThinkTagChunk.text(' 5) return;'),
      ]);
    });
  });

  group('ThinkTagStreamFilter - Orphan </think> / Assumed Thinking', () {
    test(
      'orphan </think> with assumedThinking: true and suppressReasoning: true',
      () {
        final filter = ThinkTagStreamFilter(
          assumedThinking: true,
          suppressReasoning: true,
        );
        final chunks = <ThinkTagChunk>[];

        chunks.addAll(
          filter.feed(
            'The user said "اهلا". I should reply in Arabic.</think>!أهلاً بك',
          ),
        );
        chunks.addAll(filter.flush());

        expect(chunks, [const ThinkTagChunk.text('!أهلاً بك')]);
      },
    );

    test('orphan </think> split across chunks with assumedThinking: true', () {
      final filter = ThinkTagStreamFilter(
        assumedThinking: true,
        suppressReasoning: true,
      );
      final chunks = <ThinkTagChunk>[];

      chunks.addAll(filter.feed('The user said "اهلا".'));
      chunks.addAll(filter.feed(' I should reply in Arabic.'));
      chunks.addAll(filter.feed('</th'));
      chunks.addAll(filter.feed('ink>!أهلاً بك كيف يمكنني مساعدتك؟'));
      chunks.addAll(filter.flush());

      expect(chunks, [
        const ThinkTagChunk.text('!أهلاً بك كيف يمكنني مساعدتك؟'),
      ]);
    });

    test(
      'orphan </think> with assumedThinking: true and suppressReasoning: false',
      () {
        final filter = ThinkTagStreamFilter(
          assumedThinking: true,
          suppressReasoning: false,
        );
        final chunks = <ThinkTagChunk>[];

        chunks.addAll(filter.feed('Reasoning step 1.'));
        chunks.addAll(filter.feed(' Reasoning step 2.</think>Final answer'));
        chunks.addAll(filter.flush());

        expect(chunks, [
          const ThinkTagChunk.reasoningStart(),
          const ThinkTagChunk.reasoning('Reasoning step 1.'),
          const ThinkTagChunk.reasoning(' Reasoning step 2.'),
          const ThinkTagChunk.reasoningEnd(),
          const ThinkTagChunk.text('Final answer'),
        ]);
      },
    );

    test(
      'assumedThinking: true but model does NOT emit </think> (flushes as text on end)',
      () {
        final filter = ThinkTagStreamFilter(
          assumedThinking: true,
          suppressReasoning: true,
        );
        final chunks = <ThinkTagChunk>[];

        chunks.addAll(filter.feed('Direct answer without thinking tags.'));
        chunks.addAll(filter.flush());

        expect(chunks, [
          const ThinkTagChunk.text('Direct answer without thinking tags.'),
        ]);
      },
    );

    test('handles <thought> and <thinking> synonyms', () {
      final filter = ThinkTagStreamFilter(suppressReasoning: true);
      final chunks = <ThinkTagChunk>[];

      chunks.addAll(filter.feed('<thought>Deep thought</thought>Response 1'));
      chunks.addAll(
        filter.feed('<thinking>Another thought</thinking>Response 2'),
      );
      chunks.addAll(filter.flush());

      expect(chunks, [
        const ThinkTagChunk.text('Response 1'),
        const ThinkTagChunk.text('Response 2'),
      ]);
    });
  });
}
