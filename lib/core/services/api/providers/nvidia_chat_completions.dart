import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../build_x_config.dart';
import '../../build_x_secure_store.dart';
import '../build_x_api_exception.dart';
import '../chat_api_helpers.dart' show ToolCallHandler;
import '../generation/tool_loop_runner.dart' show ExecutedClientTool;
import '../stream/stream_chunk.dart';
import '../stream/stream_chunk_emit.dart' show emitToolCall;
import '../stream/think_tag_stream_filter.dart';
import 'openai/openai_tool_transcript.dart' show openaiToolResultMessages;
import '../../../utils/multimodal_input_utils.dart';
import '../../../../utils/mcp_structured_image.dart' show ClientToolResult;
import '../../../../utils/sandbox_path_resolver.dart';

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
    List<String>? userImagePaths,
    int? thinkingBudget,
  }) async* {
    var formattedMessages = await _formatMessages(messages, userImagePaths: userImagePaths);

    final hasImages = formattedMessages.any((m) {
      final content = m['content'];
      return content is List &&
          content.any((p) => p is Map && p['type'] == 'image_url');
    });

    final effectiveModel = hasImages
        ? BuildXConfig.visionModelId
        : ((modelId != null && modelId.isNotEmpty)
            ? modelId
            : BuildXConfig.chatModelId);
    final isGlm = effectiveModel.contains('glm');

    final effectiveTemp = hasImages
        ? 0.2
        : (temperature ??
            (isGlm ? BuildXConfig.chatTemperature : BuildXConfig.workTemperature));
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

    final hasSystem = formattedMessages.any((m) => m['role'] == 'system');
    if (!hasSystem) {
      formattedMessages = [
        {
          'role': 'system',
          'content': hasImages
              ? 'You are Build X. You have full multimodal vision capabilities. Analyze the provided image and explain what is shown clearly, accurately, and concisely in natural Arabic. Do not repeat phrases. Be direct.'
              : BuildXConfig.chatSystemPrompt,
        },
        ...formattedMessages,
      ];
    }

    final String effectiveEffort;
    if (extraBody?['reasoning_effort'] != null) {
      effectiveEffort = extraBody!['reasoning_effort'].toString();
    } else if (thinkingBudget != null && thinkingBudget > 0 && !suppressReasoning) {
      if (thinkingBudget <= 1024) {
        effectiveEffort = 'low';
      } else if (thinkingBudget <= 16000) {
        effectiveEffort = 'medium';
      } else if (thinkingBudget <= 32000) {
        effectiveEffort = 'high';
      } else {
        effectiveEffort = 'max';
      }
    } else {
      effectiveEffort = 'none';
    }
    final isThinkingEnabled = effectiveEffort != 'none' && !suppressReasoning;

    final requestBody = <String, dynamic>{
      'model': effectiveModel,
      'messages': formattedMessages,
      'stream': effectiveStream,
      'temperature': effectiveTemp,
      'top_p': effectiveTopP,
      'max_tokens': effectiveMaxTokens,
      'reasoning_effort': effectiveEffort,
      if (!hasImages && isGlm)
        'chat_template_kwargs': isThinkingEnabled
            ? {
                'enable_thinking': true,
                if (effectiveEffort == 'high' || effectiveEffort == 'max')
                  'deep_reasoning': true,
              }
            : {'clear_thinking': true},
      if (!hasImages && !isGlm)
        'chat_template_kwargs': {
          'enable_thinking': isThinkingEnabled,
          'force_nonempty_content': true,
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
      // Production path: authenticated Supabase Edge Function streams real-time SSE.
      try {
        final supabase = Supabase.instance.client;
        final session = supabase.auth.currentSession;
        final token = session?.accessToken;
        const envUrl = String.fromEnvironment('SUPABASE_URL');
        const envKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
        const envAnon = String.fromEnvironment('SUPABASE_ANON_KEY');
        final resolvedUrl = envUrl.isNotEmpty ? envUrl : 'https://wwiognlfiqruvcfrbler.supabase.co';
        final resolvedKey = envKey.isNotEmpty
            ? envKey
            : (envAnon.isNotEmpty
                ? envAnon
                : 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind3aW9nbmxmaXFydXZjZnJibGVyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAyNzAxMzQsImV4cCI6MjEwNTg0NjEzNH0.L42PZmBQOg0YYAmcu9VCAyE7Q1LLnJb3VSI5TjDSpew');
        final functionUrl = '$resolvedUrl/functions/v1/nvidia-chat';

        final request = http.Request('POST', Uri.parse(functionUrl))
          ..headers.addAll({
            'Authorization': 'Bearer ${token ?? resolvedKey}',
            'apikey': resolvedKey,
            'Content-Type': 'application/json',
            'Accept': effectiveStream ? 'text/event-stream' : 'application/json',
          })
          ..body = jsonEncode(requestBody);

        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 120));

        if (response.statusCode < 200 || response.statusCode >= 300) {
          final errorBody = await response.stream.bytesToString();
          throw BuildXApiException.fromHttp(
            statusCode: response.statusCode,
            responseBody: errorBody,
          );
        }
        eventStream = response.stream;
      } on BuildXApiException {
        rethrow;
      } catch (error) {
        throw BuildXApiException.network(error);
      }
    }

    var hasEmittedReasoningStart = false;
    var hasEmittedReasoningEnd = false;
    var hasEmittedTextStart = false;
    var emittedText = false;
    final pendingToolCalls = <int, _NvidiaPendingToolCall>{};
    final thinkFilter = ThinkTagStreamFilter(
      assumedThinking: isThinkingEnabled, // If thinking mode is active, begin in thinking mode
      suppressReasoning: false, // Route thinking tags to ReasoningStart/Delta
    );

    final guardedEventStream = eventStream.timeout(
      const Duration(seconds: 120),
      onTimeout: (sink) {
        sink.addError(
          TimeoutException('The NVIDIA stream was idle for 120 seconds.'),
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
          // Internal reasoning tracking: emit ReasoningStart/Delta so it stays inside "Thinking"
          final reasoningContent =
              (delta['reasoning_content'] ?? delta['reasoning'])?.toString() ??
              '';
          if (reasoningContent.isNotEmpty) {
            if (!hasEmittedReasoningStart) {
              hasEmittedReasoningStart = true;
              yield const ReasoningStart(id: 'nvidia-reasoning');
            }
            yield ReasoningDelta(id: 'nvidia-reasoning', text: reasoningContent);
            onReasoningDelta?.call(reasoningContent);
          }

          // Tool calls tracking (e.g. search_web)
          if (delta['tool_calls'] is List) {
            final toolCalls = delta['tool_calls'] as List;
            for (final tc in toolCalls) {
              if (tc is! Map) continue;
              final index = (tc['index'] is int)
                  ? (tc['index'] as int)
                  : (int.tryParse(tc['index']?.toString() ?? '0') ??
                      pendingToolCalls.length);
              final id = (tc['id'] ?? '').toString();
              final fn = tc['function'] as Map?;
              final name = (fn?['name'] ?? '').toString();
              final argsDelta = (fn?['arguments'] ?? '').toString();

              var call = pendingToolCalls[index];
              if (call == null) {
                call = _NvidiaPendingToolCall(
                  id: id.isNotEmpty
                      ? id
                      : 'call_${DateTime.now().millisecondsSinceEpoch}_$index',
                  name: name,
                );
                pendingToolCalls[index] = call;
              } else {
                if (id.isNotEmpty && call.id.startsWith('call_')) {
                  call.id = id;
                }
                if (name.isNotEmpty && call.name.isEmpty) {
                  call.name = name;
                }
              }

              if (call.name.isNotEmpty && !call.started) {
                call.started = true;
                if (hasEmittedReasoningStart && !hasEmittedReasoningEnd) {
                  hasEmittedReasoningEnd = true;
                  yield const ReasoningEnd(id: 'nvidia-reasoning');
                }
                yield ToolCallStart(id: call.id, toolName: call.name);
                emittedText = true;
              }

              if (argsDelta.isNotEmpty) {
                call.arguments.write(argsDelta);
                yield ToolCallDelta(id: call.id, inputDelta: argsDelta);
                emittedText = true;
              }
            }
          }

          // Final Answer Content (filtered for inline think tags / orphan </think>)
          final content = delta['content']?.toString() ?? '';
          if (content.isNotEmpty) {
            final chunks = thinkFilter.feed(content);
            for (final chunk in chunks) {
              if (chunk.type == ThinkTagChunkType.reasoningStart) {
                if (!hasEmittedReasoningStart) {
                  hasEmittedReasoningStart = true;
                  yield const ReasoningStart(id: 'nvidia-reasoning');
                }
              } else if (chunk.type == ThinkTagChunkType.reasoningDelta) {
                if (!hasEmittedReasoningStart) {
                  hasEmittedReasoningStart = true;
                  yield const ReasoningStart(id: 'nvidia-reasoning');
                }
                yield ReasoningDelta(id: 'nvidia-reasoning', text: chunk.text);
                onReasoningDelta?.call(chunk.text);
              } else if (chunk.type == ThinkTagChunkType.reasoningEnd) {
                if (hasEmittedReasoningStart && !hasEmittedReasoningEnd) {
                  hasEmittedReasoningEnd = true;
                  yield const ReasoningEnd(id: 'nvidia-reasoning');
                }
              } else if (chunk.type == ThinkTagChunkType.textDelta &&
                  chunk.text.isNotEmpty) {
                if (hasEmittedReasoningStart && !hasEmittedReasoningEnd) {
                  hasEmittedReasoningEnd = true;
                  yield const ReasoningEnd(id: 'nvidia-reasoning');
                }
                if (!hasEmittedTextStart) {
                  hasEmittedTextStart = true;
                  yield const TextStart('nvidia-text');
                }
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
        if (hasEmittedReasoningStart && !hasEmittedReasoningEnd) {
          hasEmittedReasoningEnd = true;
          yield const ReasoningEnd(id: 'nvidia-reasoning');
        }
        if (!hasEmittedTextStart) {
          hasEmittedTextStart = true;
          yield const TextStart('nvidia-text');
        }
        emittedText = true;
        yield TextDelta(id: 'nvidia-text', text: chunk.text);
      }
    }

    if (hasEmittedReasoningStart && !hasEmittedReasoningEnd) {
      hasEmittedReasoningEnd = true;
      yield const ReasoningEnd(id: 'nvidia-reasoning');
    }

    // Complete pending tool call ends
    for (final call in pendingToolCalls.values) {
      if (call.started && !call.ended) {
        call.ended = true;
        yield ToolCallEnd(call.id);
      }
    }

    // Execute tool calls and stream follow-up round to produce final response
    if (pendingToolCalls.isNotEmpty && onToolCall != null) {
      final executed = <ExecutedClientTool>[];
      for (final call in pendingToolCalls.values) {
        Map<String, dynamic> arguments = {};
        try {
          final str = call.arguments.toString().trim();
          if (str.isNotEmpty) {
            arguments = (jsonDecode(str) as Map).cast<String, dynamic>();
          }
        } catch (_) {}
        final emitCall = emitToolCall(
          id: call.id,
          name: call.name,
          arguments: arguments,
        );
        final raw = await onToolCall(call.name, arguments, toolCallId: call.id);
        final parsed = ClientToolResult.fromHandler(raw);
        final executedItem = ExecutedClientTool(
          call: emitCall,
          content: parsed.content,
          metadata: parsed.metadata,
        );
        executed.add(executedItem);
        yield ToolCallResult(
          id: emitCall.id,
          output: executedItem.content,
          metadata: executedItem.metadata,
        );
      }

      final assistantToolCalls = <Map<String, dynamic>>[];
      for (final call in pendingToolCalls.values) {
        assistantToolCalls.add({
          'id': call.id,
          'type': 'function',
          'function': {
            'name': call.name,
            'arguments': call.arguments.toString(),
          },
        });
      }

      final followUpMessages = <Map<String, dynamic>>[
        ...formattedMessages,
        {
          'role': 'assistant',
          'content': null,
          'tool_calls': assistantToolCalls,
        },
        ...openaiToolResultMessages(executed),
      ];

      yield* send(
        client: client,
        messages: followUpMessages,
        modelId: effectiveModel,
        temperature: effectiveTemp,
        topP: effectiveTopP,
        maxTokens: effectiveMaxTokens,
        stream: effectiveStream,
        extraBody: extraBody,
        localConversationId: localConversationId,
        persistConversation: persistConversation,
        apiKeyOverride: apiKeyOverride,
        tools: null,
        onToolCall: null,
        suppressReasoning: true,
        thinkingBudget: 0,
      );
      return;
    }

    if (!emittedText && pendingToolCalls.isEmpty) {
      if (!hasEmittedTextStart) {
        hasEmittedTextStart = true;
        yield const TextStart('nvidia-text');
      }
      yield const TextDelta(
        id: 'nvidia-text',
        text: 'أهلاً بك! كيف يمكنني مساعدتك اليوم؟',
      );
      emittedText = true;
    }

    if (hasEmittedTextStart) {
      yield const TextEnd('nvidia-text');
    }
  }

  static String _resolveFilePath(String rawPath) {
    var p = rawPath.trim();
    if (p.startsWith('file://')) {
      try {
        p = Uri.parse(p).toFilePath();
      } catch (_) {
        p = p.substring(7);
      }
    }
    return p;
  }

  static Future<Uint8List?> _loadImageBytes(String rawSource) async {
    final s = rawSource.trim();
    if (s.isEmpty) return null;

    if (s.startsWith('data:image/')) {
      final comma = s.indexOf(',');
      if (comma != -1) {
        try {
          return base64Decode(s.substring(comma + 1));
        } catch (_) {}
      }
    }

    if (s.startsWith('http://') || s.startsWith('https://')) {
      try {
        final res = await http.get(Uri.parse(s)).timeout(const Duration(seconds: 15));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          return res.bodyBytes;
        }
      } catch (_) {}
    }

    final candidates = [
      s,
      _resolveFilePath(s),
      SandboxPathResolver.resolveForIo(s),
      SandboxPathResolver.fix(s),
    ];
    for (final cand in candidates) {
      if (cand == null || cand.isEmpty) continue;
      try {
        final file = File(cand);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) return bytes;
        }
      } catch (_) {}
    }
    return null;
  }

  static Future<Map<String, dynamic>?> _prepareSingleVisionImagePart(
    List<String> rawImageSources,
  ) async {
    if (rawImageSources.isEmpty) return null;

    final bytesList = <Uint8List>[];
    for (final src in rawImageSources) {
      final bytes = await _loadImageBytes(src);
      if (bytes != null && bytes.isNotEmpty) {
        bytesList.add(bytes);
      }
    }

    if (bytesList.isEmpty) return null;

    final decodedList = <img.Image>[];
    for (final b in bytesList) {
      try {
        final d = img.decodeImage(b);
        if (d != null) decodedList.add(d);
      } catch (_) {}
    }

    if (decodedList.isEmpty) {
      final b64 = base64Encode(bytesList.first);
      return {
        'count': 1,
        'url': 'data:image/jpeg;base64,$b64',
      };
    }

    if (decodedList.length == 1) {
      final im = decodedList.first;
      final normalized = (im.width > 1920 || im.height > 1920)
          ? img.copyResize(
              im,
              width: im.width > im.height ? 1920 : null,
              height: im.height >= im.width ? 1920 : null,
            )
          : im;
      final jpg = img.encodeJpg(normalized, quality: 85);
      return {
        'count': 1,
        'url': 'data:image/jpeg;base64,${base64Encode(jpg)}',
      };
    }

    // 2 or more images: stitch horizontally side-by-side onto a composite canvas
    const targetHeight = 768;
    const gap = 16;
    final resizedImages = <img.Image>[];
    int totalWidth = 0;
    for (final im in decodedList) {
      final r = (im.height == targetHeight)
          ? im
          : img.copyResize(im, height: targetHeight);
      resizedImages.add(r);
      totalWidth += r.width;
    }
    totalWidth += gap * (resizedImages.length - 1);

    final canvas = img.Image(width: totalWidth, height: targetHeight);
    img.fill(canvas, color: img.ColorRgb8(24, 24, 27));

    int currentX = 0;
    for (final pic in resizedImages) {
      img.compositeImage(canvas, pic, dstX: currentX, dstY: 0);
      currentX += pic.width + gap;
    }

    final compositeJpg = img.encodeJpg(canvas, quality: 85);
    return {
      'count': decodedList.length,
      'url': 'data:image/jpeg;base64,${base64Encode(compositeJpg)}',
    };
  }

  static Future<List<Map<String, dynamic>>> _formatMessages(
    List<Map<String, dynamic>> messages, {
    List<String>? userImagePaths,
  }) async {
    final list = <Map<String, dynamic>>[];

    // Identify last user turn index
    int lastUserIdx = -1;
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i]['role'] == 'user') {
        lastUserIdx = i;
        break;
      }
    }

    for (int i = 0; i < messages.length; i++) {
      final m = messages[i];
      final role = m['role']?.toString() ?? 'user';
      var textContent = _contentText(m['content']);

      // Collect image paths for this message turn
      final imagePaths = <String>[];
      final rawMedia = m[multimodalInternalMediaPathsKey] ??
          m['_kelivo_media_paths'] ??
          m['_build_x_media_paths'] ??
          m['internal_media_paths'] ??
          m['media_paths'] ??
          m['image_paths'];
      final parsedRefs = parseInternalMediaRefs(rawMedia);
      for (final ref in parsedRefs) {
        final u = ref.uri.trim();
        if (u.isNotEmpty) {
          imagePaths.add(u);
        }
      }
      if (rawMedia is List && parsedRefs.isEmpty) {
        for (final item in rawMedia) {
          if (item is String && item.trim().isNotEmpty) {
            imagePaths.add(item.trim());
          } else if (item is Map) {
            final u = (item['uri'] ?? item['path'] ?? '').toString().trim();
            if (u.isNotEmpty) imagePaths.add(u);
          }
        }
      }

      // If this is the last user turn, merge userImagePaths
      final isLatestUserTurn = (i == lastUserIdx);
      if (isLatestUserTurn && userImagePaths != null) {
        for (final p in userImagePaths) {
          final s = p.trim();
          if (s.isNotEmpty && !imagePaths.contains(s)) {
            imagePaths.add(s);
          }
        }
      }

      // Preserve document references in text
      final docs =
          m['multimodal_internal_document_paths'] ?? m['document_paths'];
      if (docs is List && docs.isNotEmpty) {
        final names = docs
            .map((e) => e.toString().split(RegExp(r'[/\\]')).last)
            .join(', ');
        textContent = textContent.isEmpty
            ? '[Attached document(s): $names]'
            : '$textContent\n[Attached document(s): $names]';
      }

      // Historical turns: never forward image_url parts, keep only textual summary
      if (!isLatestUserTurn && imagePaths.isNotEmpty) {
        const notice = '[صورة سابقة مرفقة من المستخدم]';
        textContent = textContent.isEmpty ? notice : '$textContent\n$notice';
        if (textContent.isNotEmpty) {
          list.add({'role': role, 'content': textContent});
        }
        continue;
      }

      // Latest user turn with images: convert to exactly 1 composite image_url
      if (isLatestUserTurn && imagePaths.isNotEmpty) {
        final visionData = await _prepareSingleVisionImagePart(imagePaths);
        if (visionData != null) {
          final parts = <Map<String, dynamic>>[];
          final count = visionData['count'] as int? ?? 1;
          final dataUrl = visionData['url'] as String;

          String effectivePrompt = textContent;
          if (count > 1) {
            const multiNote =
                '[ملاحظة للنموذج: تم دمج الصور المرفقة في صورة واحدة مركبة جنباً إلى جنب للمقارنة والتحليل الفوري.]';
            effectivePrompt = effectivePrompt.isEmpty
                ? multiNote
                : '$effectivePrompt\n$multiNote';
          }
          if (effectivePrompt.isEmpty) {
            effectivePrompt =
                'يرجى قراءة هذه الصورة بدقة وتحليل محتواها بالتفصيل وشرح كل ما يظهر فيها والإجابة عن أي مسألة أو سؤال وارد فيها.';
          }

          parts.add({'type': 'text', 'text': effectivePrompt});
          parts.add({
            'type': 'image_url',
            'image_url': {'url': dataUrl},
          });

          list.add({
            'role': role,
            'content': parts,
          });
          continue;
        }
      }

      if (textContent.isNotEmpty) {
        list.add({'role': role, 'content': textContent});
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

class _NvidiaPendingToolCall {
  String id;
  String name;
  final StringBuffer arguments = StringBuffer();
  bool started = false;
  bool ended = false;
  _NvidiaPendingToolCall({required this.id, required this.name});
}
