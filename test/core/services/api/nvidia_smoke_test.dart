import 'dart:io' show Platform;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:Kelivo/core/build_x_config.dart';
import 'package:Kelivo/core/services/api/providers/nvidia_chat_completions.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk.dart';
import 'package:Kelivo/core/services/build_x_secure_store.dart';

void main() {
  test(
    'REAL NVIDIA API Smoke Test: connects to live endpoint, validates model, streams chunks and finishes',
    () async {
      // 1. Resolve key from environment or fallback
      var apiKey =
          Platform.environment['NVIDIA_API_KEY'] ??
          Platform.environment['WORK_LLM_API_KEY'] ??
          Platform.environment['BUILD_X_API_KEY'];

      if (apiKey == null || apiKey.trim().isEmpty) {
        apiKey = await BuildXSecureStore.readNvidiaKey();
      }

      final sanitizedKey = BuildXSecureStore.sanitizeApiKey(apiKey);
      if (sanitizedKey.isEmpty) {
        fail(
          'BLOCKED: real NVIDIA API smoke test could not be executed because no valid NVIDIA_API_KEY was available.',
        );
      }

      final client = http.Client();
      final chunks = <StreamChunk>[];
      final assistantContent = StringBuffer();
      final reasoningContent = StringBuffer();
      String? finishModel;

      try {
        final stream = NvidiaChatCompletions.send(
          client: client,
          messages: [
            {'role': 'user', 'content': 'Say hi in 3 words'},
          ],
          apiKeyOverride: sanitizedKey,
          suppressReasoning: false,
          onReasoningDelta: (r) => reasoningContent.write(r),
        );

        await for (final chunk in stream) {
          chunks.add(chunk);
          if (chunk is TextDelta) {
            assistantContent.write(chunk.text);
          } else if (chunk is Finish) {
            finishModel = chunk.model;
          }
        }
      } finally {
        client.close();
      }

      // ignore: avoid_print
      print('CHUNKS COUNT: ${chunks.length}');
      // ignore: avoid_print
      print('CHUNK TYPES: ${chunks.map((c) => c.runtimeType).toList()}');
      // ignore: avoid_print
      print('REASONING CONTENT: "$reasoningContent"');
      // ignore: avoid_print
      print('ASSISTANT CONTENT: "$assistantContent"');

      // Assertions per Section 3 of specification:
      // 1. request reaches NVIDIA and no 401 occurred (if it threw, test failed)
      // 2. HTTP status is successful (stream emitted chunks)
      expect(
        chunks,
        isNotEmpty,
        reason: 'At least one streamed chunk must be received',
      );

      // 3. selected model is nvidia/nemotron-3-ultra-550b-a55b
      expect(
        finishModel ?? BuildXConfig.modelId,
        equals('nvidia/nemotron-3-ultra-550b-a55b'),
        reason: 'Selected model must be nvidia/nemotron-3-ultra-550b-a55b',
      );

      // 4. at least one chunk is received
      expect(chunks.any((c) => c is TextStart), isTrue);

      // 5. visible assistant content becomes non-empty
      final contentStr = assistantContent.toString().trim();
      expect(
        contentStr.isNotEmpty,
        isTrue,
        reason: 'Visible assistant content must be non-empty',
      );

      // 6. stream terminates correctly
      expect(
        chunks.any((c) => c is Finish),
        isTrue,
        reason: 'Stream must terminate with Finish',
      );

      // 7. No 401 occurred (verified by reaching here)
      // 8. No unhandled parser exception occurred (verified by reaching here)
      // ignore: avoid_print
      print(
        'SMOKE TEST SUCCESS: Received assistant content: "$contentStr" from model: ${BuildXConfig.modelId}',
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
    skip: Platform.environment['RUN_LIVE_NVIDIA_TESTS'] != '1'
        ? 'Set RUN_LIVE_NVIDIA_TESTS=1 to call the paid live NVIDIA API.'
        : false,
  );
}
