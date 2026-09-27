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

/// Client for NVIDIA NIM OpenAI-compatible Chat Completions API.
/// Supports both:
/// - Chat Mode: z-ai/glm-5.3-flash
/// - Work Mode: nvidia/nemotron-3-ultra-550b-a55b
abstract final class NvidiaChatCompletions {
  static Stream<StreamChunk> send({
    required http.Client client,
    required List<Map<String, dynamic>> messages,
    String? modelId,
    double? temperature,
    double? topP,
    int? maxTokens,
    bool? stream,
    Map<String, dynamic>? extraBody,
    String? localConversationId,
    bool persistConversation = true,
    String? apiKeyOverride,
    List<Map<String, dynamic>>? tools,
    ToolCallHandler? onToolCall,
    bool suppressReasoning = true,
    void Function(String reasoningText)? onReasoningDelta,
  }) async* {
    final effectiveModel = (modelId != null && modelId.isNotEmpty)
        ? modelId
        : BuildXConfig.chatModelId;
    final isGlm = effectiveModel.contains('glm');

    final effectiveTemp =
        temperature ??
        (isGlm ? BuildXConfig.chatTemperature : BuildXConfig.workTemperature);
    final effectiveTopP =
        topP ?? (isGlm ? BuildXConfig.chatTopP : BuildXConfig.workTopP);
    final effectiveMaxTokens =
        maxTokens ??
        (isGlm ? BuildXConfig.chatMaxTokens : BuildXConfig.workMaxTokens);
    final effectiveStream =
        stream ?? (isGlm ? BuildXConfig.chatStream : BuildXConfig.workStream);

    final candidateOverride =
        (apiKeyOverride != null && apiKeyOverride.trim().isNotEmpty)
        ? BuildXSecureStore.sanitizeApiKey(apiKeyOverride)
        : null;
    final rawKey =
        candidateOverride ??
        await BuildXSecureStore.readNvidiaKey(modelId: effectiveModel);
    final apiKey = BuildXSecureStore.sanitizeApiKey(rawKey);

    var formattedMessages = _formatMessages(messages);
    if (isGlm) {
      final hasSystem = formattedMessages.any((m) => m['role'] == 'system');
      if (!hasSystem) {
        formattedMessages = [
          {'role': 'system', 'content': BuildXConfig.chatSystemPrompt},
          ...formattedMessages,
        ];
      }
    }

    final requestBody = <String, dynamic>{
      'model': effectiveModel,
      'messages': formattedMessages,
      'stream': effectiveStream,
      'temperature': effectiveTemp,
      'top_p': effectiveTopP,
      'max_tokens': effectiveMaxTokens,
      if (isGlm) 'reasoning_effort': suppressReasoning ? 'none' : 'low',
      if (isGlm) 'chat_template_kwargs': {'clear_thinking': true},
      if (!isGlm) ...{
        'chat_template_kwargs': {
          'enable_thinking': !suppressReasoning,
          if (tools != null && tools.isNotEmpty) 'force_nonempty_content': true,
        },
      },
      if (extraBody != null) ...extraBody,
      if (tools != null && tools.isNotEmpty) 'tools': tools,
    };

    final Stream<List<int>> eventStream;
    if (apiKey.isNotEmpty) {
      // Direct BYOK / local development path. Credentials stay off client bundle.
      final uri = Uri.parse(BuildXConfig.chatCompletionsEndpoint);
      final request = http.Request('POST', uri)
        ..headers.addAll({
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'Accept': effectiveStream ? 'text/event-stream' : 'application/json',
        })
        ..body = jsonEncode(requestBody);

      final http.StreamedResponse response;
      try {
        response = await client
            .send(request)
            .timeout(const Duration(seconds: 40));
      } catch (e) {
        if (e is BuildXApiException) rethrow;
        if (e.runtimeType.toString().contains('TestFailure')) rethrow;
        throw BuildXApiException.network(e);
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errorBody = await response.stream.bytesToString();
        debugPrint('NVIDIA API request failed (HTTP ${response.statusCode}).');
        throw BuildXApiException.fromHttp(
          statusCode: response.statusCode,
          responseBody: errorBody,
        );
      }
      eventStream = response.stream;
    } else {
      // Production path: authenticated Supabase Edge Function owns secrets.
      try {
        final supabase = Supabase.instance.client;
        if (supabase.auth.currentSession == null) {
          throw const BuildXApiException(
            userMessage: 'The AI service could not authenticate.',
            statusCode: 401,
          );
        }
        final response = await supabase.functions
            .invoke(
              'nvidia-chat',
              headers: {
                'Accept': effectiveStream
                    ? 'text/event-stream'
                    : 'application/json',
              },
              body: requestBody,
            )
            .timeout(const Duration(seconds: 135));
        if (response.status < 200 || response.status >= 300) {
          throw BuildXApiException.fromHttp(
            statusCode: response.status,
            responseBody: jsonEncode(response.data),
          );
        }
        final data = response.data;
        if (data is Stream<List<int>>) {
          eventStream = data;
        } else if (data is Map<String, dynamic> || data is String) {
          final encoded = data is String ? data : jsonEncode(data);
          eventStream = Stream.value(utf8.encode(encoded));
        } else {
          throw const BuildXApiException(
            userMessage: 'Connection interrupted. Please try again.',
            statusCode: 502,
          );
        }
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
    final thinkFilter = ThinkTagStreamFilter(
      assumedThinking: !isGlm && !suppressReasoning,
      suppressReasoning: true, // Never expose raw chain-of-thought to the user
    );

    final guardedEventStream = eventStream.timeout(
      const Duration(seconds: 90),
      onTimeout: (sink) {
        sink.addError(
          TimeoutException('The NVIDIA stream was idle for 90 seconds.'),
        );
        sink.close();
      },
    );
    try {
      await for (final event in decodeEvents(guardedEventStream)) {
        final choices = event['choices'];
        if (choices is! List || choices.isEmpty) continue;
        final choice = choices[0];
        if (choice is! Map) continue;

        final delta =
            (choice['delta'] ?? choice['message']) as Map<String, dynamic>?;
        if (delta != null) {
          // Internal reasoning tracking if present, but never output raw reasoning to user
          final reasoningContent =
              (delta['reasoning_content'] ?? delta['reasoning'])?.toString() ??
              '';
          if (reasoningContent.isNotEmpty) {
            onReasoningDelta?.call(reasoningContent);
          }

          // Tool calls tracking (e.g. search_web)
          if (delta['tool_calls'] is List) {
            final toolCalls = delta['tool_calls'] as List;
            for (final tc in toolCalls) {
              if (tc is Map) {
                final id = (tc['id'] ?? '').toString();
                final fn = tc['function'] as Map?;
                final name = (fn?['name'] ?? '').toString();
                final args = (fn?['arguments'] ?? '').toString();
                if (name.isNotEmpty) {
                  yield ToolCallStart(id: id, toolName: name);
                  if (args.isNotEmpty) {
                    yield ToolCallDelta(id: id, inputDelta: args);
                  }
                  yield ToolCallEnd(id);
                  emittedText = true;
                }
              }
            }
          }

          // Final Answer Content (filtered for inline think tags / orphan </think>)
          final content = delta['content']?.toString() ?? '';
          if (content.isNotEmpty) {
            final chunks = thinkFilter.feed(content);
            for (final chunk in chunks) {
              if (chunk.type == ThinkTagChunkType.textDelta &&
                  chunk.text.isNotEmpty) {
                emittedText = true;
                yield TextDelta(id: 'nvidia-text', text: chunk.text);
              }
            }
          }
        }

        final finishReason = choice['finish_reason']?.toString();
        if (finishReason != null && finishReason.isNotEmpty) {
          yield Finish(finishReason: finishReason, model: effectiveModel);
        }
      }
    } on TimeoutException catch (error) {
      throw BuildXApiException.network(error);
    }

    final finalChunks = thinkFilter.flush();
    for (final chunk in finalChunks) {
      if (chunk.type == ThinkTagChunkType.textDelta && chunk.text.isNotEmpty) {
        emittedText = true;
        yield TextDelta(id: 'nvidia-text', text: chunk.text);
      }
    }

    if (!emittedText) {
      throw BuildXApiException.emptyResponse();
    }

    yield const TextEnd('nvidia-text');
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

  /// Decodes both SSE event streams and standard JSON responses safely.
  static Stream<Map<String, dynamic>> decodeEvents(
    Stream<List<int>> bytes,
  ) async* {
    final buffer = StringBuffer();
    bool hasSeenSseData = false;

    await for (final line
        in bytes
            .cast<List<int>>()
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())) {
      final trimmed = line.trim();
      buffer.writeln(line);

      if (trimmed.isEmpty) {
        continue;
      }

      if (trimmed.startsWith('data:')) {
        hasSeenSseData = true;
        final payload = trimmed.substring(5).trim();
        if (payload == '[DONE]') {
          return;
        }
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map<String, dynamic>) {
            yield decoded;
          }
        } catch (_) {}
      }
    }

    // If no SSE data: prefix lines were observed, parse the entire accumulated buffer as JSON
    if (!hasSeenSseData && buffer.isNotEmpty) {
      final raw = buffer.toString().trim();
      if (raw.isNotEmpty && raw.startsWith('{') && raw.endsWith('}')) {
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
