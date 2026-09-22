import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../../models/auto_retry_options.dart';
import '../../providers/settings_provider.dart';
import 'chat_api_helpers.dart';
import 'generation/text_generation_result.dart';
import 'providers/claude_official.dart' show normalizeClaudeImageMime;
import 'providers/google_vertex.dart' show shouldAttachVertexMediaAuth;
import 'providers/nvidia_chat_completions.dart';
import 'providers/openai/openai_vendor_compat.dart'
    show isLongCatHost, shouldIncludeStreamingUsageOptions;
import 'stream/stream_chunk.dart';
import 'stream/stream_chunk_handler.dart';

export 'chat_api_helpers.dart' show ToolCallHandler;
export 'generation/text_generation_result.dart';
export 'generation/tool_loop_runner.dart';
export 'stream/stream_chunk_emit.dart';

/// Single outbound path for all model text generation in Build X.
class ChatApiService {
  static final Map<String, http.Client> _activeClients = {};

  @visibleForTesting
  static bool shouldAttachVertexMediaAuthForTest(Uri uri) =>
      shouldAttachVertexMediaAuth(uri);

  @visibleForTesting
  static String normalizeClaudeImageMimeForTest(String mime) =>
      normalizeClaudeImageMime(mime);

  @visibleForTesting
  static bool isLongCatHostForTest(String baseUrl) => isLongCatHost(baseUrl);

  @visibleForTesting
  static bool shouldIncludeStreamingUsageOptionsForTest(String host) =>
      shouldIncludeStreamingUsageOptions(host);

  static bool supportsOpenAIImagesApiRouting(
    ProviderConfig config,
    String modelId,
  ) => false;

  static void cancelRequest(String requestId) {
    _activeClients.remove(requestId.trim())?.close();
  }

  static Stream<StreamChunk> sendMessageStream({
    required ProviderConfig config,
    required String modelId,
    required List<Map<String, dynamic>> messages,
    List<String>? userImagePaths,
    int? thinkingBudget,
    double? temperature,
    double? topP,
    int? maxTokens,
    List<Map<String, dynamic>>? tools,
    ToolCallHandler? onToolCall,
    Map<String, String>? extraHeaders,
    Map<String, dynamic>? extraBody,
    bool stream = true,
    String? requestId,
    String? conversationId,
    bool allowImagesApiRouting = true,
    bool ocrActive = false,
    bool builtInSearchOnly = false,
    bool skipImageParsing = false,
    bool parseMarkdownImageLinks = true,
    AutoRetryOptions? retryOverride,
    bool persistConversation = true,
  }) async* {
    final client = http.Client();
    final id = requestId?.trim() ?? '';
    if (id.isNotEmpty) {
      _activeClients.remove(id)?.close();
      _activeClients[id] = client;
    }
    try {
      yield* NvidiaChatCompletions.send(
        client: client,
        messages: messages,
        localConversationId: conversationId,
        persistConversation: persistConversation,
        apiKeyOverride:
            config.apiKey.trim().isNotEmpty ? config.apiKey.trim() : null,
        tools: tools,
        onToolCall: onToolCall,
        suppressReasoning: true,
      );
    } finally {
      if (id.isNotEmpty && identical(_activeClients[id], client)) {
        _activeClients.remove(id);
      }
      client.close();
    }
  }

  static Future<TextGenerationResult> generateMessage({
    required ProviderConfig config,
    required String modelId,
    required List<Map<String, dynamic>> messages,
    List<String>? userImagePaths,
    int? thinkingBudget,
    double? temperature,
    double? topP,
    int? maxTokens,
    List<Map<String, dynamic>>? tools,
    ToolCallHandler? onToolCall,
    Map<String, String>? extraHeaders,
    Map<String, dynamic>? extraBody,
    String? requestId,
    String? conversationId,
    bool allowImagesApiRouting = true,
    bool ocrActive = false,
    bool builtInSearchOnly = false,
    bool skipImageParsing = false,
    bool parseMarkdownImageLinks = true,
    AutoRetryOptions? retryOverride,
    void Function(RetryPending? pending)? onRetry,
    bool persistConversation = true,
  }) async {
    final handler = StreamChunkHandler(onRetry: onRetry);
    await for (final chunk in sendMessageStream(
      config: config,
      modelId: modelId,
      messages: messages,
      userImagePaths: userImagePaths,
      thinkingBudget: thinkingBudget,
      temperature: temperature,
      topP: topP,
      maxTokens: maxTokens,
      tools: tools,
      onToolCall: onToolCall,
      extraHeaders: extraHeaders,
      extraBody: extraBody,
      requestId: requestId,
      conversationId: conversationId,
      allowImagesApiRouting: allowImagesApiRouting,
      ocrActive: ocrActive,
      builtInSearchOnly: builtInSearchOnly,
      skipImageParsing: skipImageParsing,
      parseMarkdownImageLinks: parseMarkdownImageLinks,
      retryOverride: retryOverride,
      persistConversation: persistConversation,
    )) {
      handler.handle(chunk);
    }
    return handler.toResult();
  }

  /// Utility requests are independent of the user's persistent chat thread.
  static Future<String> generateText({
    required ProviderConfig config,
    required String modelId,
    required String prompt,
    String? conversationId,
    Map<String, String>? extraHeaders,
    Map<String, dynamic>? extraBody,
    int? thinkingBudget,
    bool skipImageParsing = false,
  }) async {
    final result = await generateMessage(
      config: config,
      modelId: modelId,
      messages: [
        {'role': 'user', 'content': prompt},
      ],
      persistConversation: false,
    );
    return result.text;
  }
}
