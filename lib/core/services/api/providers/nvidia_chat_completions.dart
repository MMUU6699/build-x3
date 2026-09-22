import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../build_x_config.dart';
import '../../build_x_secure_store.dart';
import '../chat_api_helpers.dart' show ToolCallHandler;
import '../stream/stream_chunk.dart';

/// Client for NVIDIA NIM OpenAI-compatible Chat Completions API with thinking support.
/// Model: nvidia/nemotron-3-ultra-550b-a55b
abstract final class NvidiaChatCompletions {
  static Stream<StreamChunk> send({
    required http.Client client,
    required List<Map<String, dynamic>> messages,
    String? localConversationId,
    bool persistConversation = true,
    String? apiKeyOverride,
    List<Map<String, dynamic>>? tools,
    ToolCallHandler? onToolCall,
    bool suppressReasoning = true,
    void Function(String reasoningText)? onReasoningDelta,
  }) async* {
    final rawKey = apiKeyOverride ?? await BuildXSecureStore.readNvidiaKey();
    final apiKey = BuildXSecureStore.sanitizeApiKey(rawKey);
    if (apiKey.isEmpty) {
      throw StateError(
        'NVIDIA API key not configured. Please add your NVIDIA API key (nvapi-...) in Settings > Build X Connection.',
      );
    }

    final formattedMessages = _formatMessages(messages);
    final uri = Uri.parse(BuildXConfig.chatCompletionsEndpoint);

    final requestBody = <String, dynamic>{
      'model': BuildXConfig.modelId,
      'messages': formattedMessages,
      'stream': true,
      'temperature': BuildXConfig.temperature,
      'top_p': BuildXConfig.topP,
      'max_tokens': BuildXConfig.maxTokens,
      'chat_template_kwargs': {
        'enable_thinking': true,
      },
      if (tools != null && tools.isNotEmpty) 'tools': tools,
    };

    final request = http.Request('POST', uri)
      ..headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      })
      ..body = jsonEncode(requestBody);

    final response = await client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorBody = await response.stream.bytesToString();
      if (response.statusCode == 401) {
        throw StateError(
          'NVIDIA API request failed (HTTP 401 Unauthorized): Authentication failed. '
          'Please verify your NVIDIA API key in Settings > Build X Connection '
          '(ensure it starts with "nvapi-" and is active at https://build.nvidia.com/settings/api-keys).',
        );
      }
      throw StateError(
        'NVIDIA API request failed (HTTP ${response.statusCode}): $errorBody',
      );
    }

    yield const TextStart('nvidia-text');
    var emittedText = false;
    var emittedReasoning = false;

    await for (final event in decodeEvents(response.stream)) {
      final choices = event['choices'];
      if (choices is! List || choices.isEmpty) continue;
      final choice = choices[0];
      if (choice is! Map) continue;

      final delta = choice['delta'];
      if (delta is Map) {
        // 1. Thinking / Reasoning content
        final reasoningContent =
            (delta['reasoning_content'] ?? delta['reasoning'])?.toString() ?? '';
        if (reasoningContent.isNotEmpty) {
          onReasoningDelta?.call(reasoningContent);
          if (!suppressReasoning) {
            if (!emittedReasoning) {
              emittedReasoning = true;
              yield const ReasoningStart(id: 'nvidia-reasoning');
            }
            yield ReasoningDelta(
              id: 'nvidia-reasoning',
              text: reasoningContent,
            );
          }
        }

        // 2. Final Answer Content
        final content = delta['content']?.toString() ?? '';
        if (content.isNotEmpty) {
          if (emittedReasoning && !suppressReasoning) {
            yield const ReasoningEnd(id: 'nvidia-reasoning');
            emittedReasoning = false;
          }
          emittedText = true;
          yield TextDelta(id: 'nvidia-text', text: content);
        }
      }

      final finishReason = choice['finish_reason']?.toString();
      if (finishReason != null && finishReason.isNotEmpty) {
        if (emittedReasoning && !suppressReasoning) {
          yield const ReasoningEnd(id: 'nvidia-reasoning');
          emittedReasoning = false;
        }
        yield Finish(finishReason: finishReason, model: BuildXConfig.modelId);
      }
    }

    if (emittedText) {
      yield const TextEnd('nvidia-text');
    }
  }

  static List<Map<String, dynamic>> _formatMessages(
    List<Map<String, dynamic>> messages,
  ) {
    final list = <Map<String, dynamic>>[];
    for (final m in messages) {
      final role = m['role']?.toString() ?? 'user';
      final content = _contentText(m['content']);
      if (content.isNotEmpty) {
        list.add({'role': role, 'content': content});
      }
    }
    if (list.isEmpty) {
      list.add({'role': 'user', 'content': 'Hello'});
    }
    return list;
  }

  static String _contentText(Object? value) {
    if (value is String) return value;
    if (value is List) return value.map(_contentText).join();
    if (value is Map) {
      if (value['text'] is String) return value['text'] as String;
      if (value['content'] != null) return _contentText(value['content']);
    }
    return '';
  }

  static Stream<Map<String, dynamic>> decodeEvents(
    Stream<List<int>> bytes,
  ) async* {
    final data = StringBuffer();
    await for (final line
        in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (data.isNotEmpty) {
          final raw = data.toString().trim();
          if (raw != '[DONE]') {
            try {
              final decoded = jsonDecode(raw);
              if (decoded is Map<String, dynamic>) {
                yield decoded;
              }
            } catch (_) {}
          }
          data.clear();
        }
        continue;
      }

      if (trimmed.startsWith('data:')) {
        final payload = trimmed.substring(5).trim();
        if (payload == '[DONE]') {
          data.clear();
          return;
        }
        if (data.isNotEmpty) data.write('\n');
        data.write(payload);
      }
    }

    if (data.isNotEmpty) {
      final raw = data.toString().trim();
      if (raw != '[DONE]') {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            yield decoded;
          }
        } catch (_) {}
      }
    }
  }
}
