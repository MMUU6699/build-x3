// ignore_for_file: avoid_print

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:Kelivo/core/services/api/providers/nvidia_chat_completions.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk.dart';
import 'package:Kelivo/core/services/build_x_secure_store.dart';

void main() {
  test('NvidiaChatCompletions.send real API integration test', () async {
    final key =
        Platform.environment['NVIDIA_API_KEY'] ??
        await BuildXSecureStore.readNvidiaKey();
    if (key.isEmpty) {
      print('Skipping test: NVIDIA_API_KEY environment variable not set.');
      return;
    }
    print('Starting test with key: nvapi-****${key.substring(key.length - 4)}');

    final client = http.Client();
    final chunks = <StreamChunk>[];
    final reasoningDeltas = <String>[];
    final textDeltas = <String>[];

    try {
      final stream = NvidiaChatCompletions.send(
        client: client,
        apiKeyOverride: key,
        messages: [
          {'role': 'user', 'content': 'Reply with exactly: BUILD_X_DART_OK'},
        ],
        suppressReasoning: false,
        onReasoningDelta: (delta) {
          reasoningDeltas.add(delta);
        },
      );

      await for (final chunk in stream) {
        chunks.add(chunk);
        if (chunk is TextDelta) {
          textDeltas.add(chunk.text);
        }
      }
    } finally {
      client.close();
    }

    print('Total chunks emitted: ${chunks.length}');
    print('Reasoning deltas count: ${reasoningDeltas.length}');
    print('Text deltas count: ${textDeltas.length}');
    final output = textDeltas.join();
    print('Output text: $output');

    expect(
      chunks.any((c) => c is TextStart),
      isTrue,
      reason: 'TextStart must be emitted',
    );
    expect(
      chunks.any((c) => c is Finish),
      isTrue,
      reason: 'Finish must be emitted',
    );
    expect(output, contains('BUILD_X_DART_OK'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
