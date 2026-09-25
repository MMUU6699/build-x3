import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../build_x_config.dart';
import '../../build_x_secure_store.dart';
import '../build_x_api_exception.dart';
import '../chat_api_helpers.dart' show ToolCallHandler;
import '../stream/stream_chunk.dart';
import '../stream/think_tag_stream_filter.dart';

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
    final candidateOverride =
        (apiKeyOverride != null && apiKeyOverride.trim().isNotEmpty)
        ? BuildXSecureStore.sanitizeApiKey(apiKeyOverride)
        : null;
    final rawKey = candidateOverride ?? await BuildXSecureStore.readNvidiaKey();
    final apiKey = BuildXSecureStore.sanitizeApiKey(rawKey);

    final formattedMessages = _formatMessages(messages);
    final requestBody = <String, dynamic>{
      'model': BuildXConfig.modelId,
      'messages': formattedMessages,
      'stream': true,
      'temperature': BuildXConfig.temperature,
      'top_p': BuildXConfig.topP,
      'max_tokens': BuildXConfig.maxTokens,
      'chat_template_kwargs': {
        'enable_thinking': true,
        if (tools != null && tools.isNotEmpty) 'force_nonempty_content': true,
      },
      if (tools != null && tools.isNotEmpty) 'tools': tools,
    };

    final Stream<List<int>> eventStream;
    if (apiKey.isNotEmpty) {
      // Explicit BYOK path. The key stays on the device and is sent directly
      // to NVIDIA; shared production credentials are never embedded here.
      final uri = Uri.parse(BuildXConfig.chatCompletionsEndpoint);
      final request = http.Request('POST', uri)
        ..headers.addAll({
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
        })
        ..body = jsonEncode(requestBody);

      final http.StreamedResponse response;
      try {
        response = await client.send(request);
      } catch (e) {
        if (e is BuildXApiException) rethrow;
        if (e.runtimeType.toString().contains('TestFailure')) rethrow;
        throw BuildXApiException.network(e);
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errorBody = await response.stream.bytesToString();
        debugPrint('NVIDIA BYOK request failed (HTTP ${response.statusCode}).');
        throw BuildXApiException.fromHttp(
          statusCode: response.statusCode,
          responseBody: errorBody,
        );
      }
      eventStream = response.stream;
    } else {
      // Default production path: the authenticated Edge Function owns the
      // shared NVIDIA credential and validates the Supabase JWT.
      try {
        final supabase = Supabase.instance.client;
        if (supabase.auth.currentSession == null) {
          throw const BuildXApiException(
            userMessage: 'يرجى تسجيل الدخول لاستخدام نموذج Build X.',
            statusCode: 401,
          );
        }
        final response = await supabase.functions.invoke(
          'nvidia-chat',
          headers: const {'Accept': 'text/event-stream'},
          body: requestBody,
        );
        if (response.status < 200 || response.status >= 300) {
          throw BuildXApiException.fromHttp(
            statusCode: response.status,
            responseBody: jsonEncode(response.data),
          );
        }
        final data = response.data;
        if (data is! Stream<List<int>>) {
          throw const BuildXApiException(
            userMessage: 'تعذر بدء بث الاستجابة من خادم Build X.',
            statusCode: 502,
          );
        }
        eventStream = data;
      } on BuildXApiException {
        rethrow;
      } on FunctionException catch (error) {
        throw BuildXApiException.fromHttp(
          statusCode: error.status,
          responseBody: error.details?.toString() ?? error.reasonPhrase ?? '',
        );
      } catch (error) {
        throw BuildXApiException.network(error);
      }
    }

    yield const TextStart('nvidia-text');
    var emittedText = false;
    var emittedReasoning = false;
    final thinkFilter = ThinkTagStreamFilter(
      assumedThinking: true,
      suppressReasoning: suppressReasoning,
    );

    await for (final event in decodeEvents(eventStream)) {
      final choices = event['choices'];
      if (choices is! List || choices.isEmpty) continue;
      final choice = choices[0];
      if (choice is! Map) continue;

      final delta = choice['delta'];
      if (delta is Map) {
        // 1. Thinking / Reasoning content from reasoning_content or reasoning fields
        final reasoningContent =
            (delta['reasoning_content'] ?? delta['reasoning'])?.toString() ??
            '';
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

        // 2. Final Answer Content (filtered for inline think tags / orphan </think>)
        final content = delta['content']?.toString() ?? '';
        if (content.isNotEmpty) {
          final chunks = thinkFilter.feed(content);
          for (final chunk in chunks) {
            switch (chunk.type) {
              case ThinkTagChunkType.reasoningStart:
                if (!suppressReasoning && !emittedReasoning) {
                  emittedReasoning = true;
                  yield const ReasoningStart(id: 'nvidia-reasoning');
                }
              case ThinkTagChunkType.reasoningDelta:
                onReasoningDelta?.call(chunk.text);
                if (!suppressReasoning) {
                  if (!emittedReasoning) {
                    emittedReasoning = true;
                    yield const ReasoningStart(id: 'nvidia-reasoning');
                  }
                  yield ReasoningDelta(
                    id: 'nvidia-reasoning',
                    text: chunk.text,
                  );
                }
              case ThinkTagChunkType.reasoningEnd:
                if (!suppressReasoning && emittedReasoning) {
                  yield const ReasoningEnd(id: 'nvidia-reasoning');
                  emittedReasoning = false;
                }
              case ThinkTagChunkType.textDelta:
                if (emittedReasoning && !suppressReasoning) {
                  yield const ReasoningEnd(id: 'nvidia-reasoning');
                  emittedReasoning = false;
                }
                emittedText = true;
                yield TextDelta(id: 'nvidia-text', text: chunk.text);
            }
          }
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

    final finalChunks = thinkFilter.flush();
    for (final chunk in finalChunks) {
      if (chunk.type == ThinkTagChunkType.textDelta) {
        emittedText = true;
        yield TextDelta(id: 'nvidia-text', text: chunk.text);
      } else if (chunk.type == ThinkTagChunkType.reasoningDelta &&
          !suppressReasoning) {
        yield ReasoningDelta(id: 'nvidia-reasoning', text: chunk.text);
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
        in bytes
            .cast<List<int>>()
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())) {
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
