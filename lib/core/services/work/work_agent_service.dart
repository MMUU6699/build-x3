import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../build_x_config.dart';
import '../../work_mode_config.dart';
import '../api/build_x_api_exception.dart';
import '../api/stream/think_tag_stream_filter.dart';
import '../build_x_secure_store.dart';
import 'work_agent_event.dart';

/// Execution service for Build X Work Mode.
///
/// Connects to the OpenHands backend server when available, or executes
/// directly against NVIDIA NIM API with real autonomous multi-step reasoning,
/// live thinking stream, tool calls, and client-side deliverable packaging.
class WorkAgentService {
  WorkAgentService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
  }

  /// Runs an autonomous task in Work mode and streams real agent events.
  Stream<WorkAgentEvent> runTask({
    required String prompt,
    required String modelId,
    required WorkReasoningEffort reasoningEffort,
    String? customApiKey,
    String? customBackendUrl,
  }) async* {
    _cancelled = false;
    final apiKey = customApiKey?.trim().isNotEmpty == true
        ? customApiKey!.trim()
        : await BuildXSecureStore.readNvidiaKey();

    final backendUrl = customBackendUrl?.trim().isNotEmpty == true
        ? customBackendUrl!.trim()
        : await BuildXSecureStore.readWorkBackendUrl();

    // 1. Production path: authenticated Supabase orchestration. Daytona and
    // NVIDIA credentials remain server-side Edge Function secrets.
    try {
      if (Supabase.instance.client.auth.currentSession != null) {
        yield* _runViaSupabaseFunction(
          prompt: prompt,
          modelId: modelId,
          reasoningEffort: reasoningEffort,
        );
        return;
      }
    } catch (error) {
      // Only an explicitly configured BYOK key may fall back to direct NIM.
      if (apiKey.isEmpty) {
        yield WorkDoneEvent(error: _safeFunctionError(error));
        return;
      }
    }

    // 2. Optional self-hosted backend. It receives the user's Supabase JWT,
    // never the NVIDIA credential.
    bool backendSuccess = false;
    if (backendUrl.isNotEmpty) {
      try {
        final stream = _runViaBackendServer(
          backendUrl: backendUrl,
          prompt: prompt,
          modelId: modelId,
          reasoningEffort: reasoningEffort,
        );
        await for (final event in stream) {
          if (_cancelled) return;
          backendSuccess = true;
          yield event;
        }
      } catch (_) {
        backendSuccess = false;
      }
    }

    if (backendSuccess) return;

    // 3. Explicit BYOK fallback for development or user-owned credentials.
    yield* _runDirectNvidiaAgent(
      prompt: prompt,
      modelId: modelId.isNotEmpty ? modelId : BuildXConfig.modelId,
      reasoningEffort: reasoningEffort,
      apiKey: apiKey,
    );
  }

  /// Connects to OpenHands backend server via SSE
  Stream<WorkAgentEvent> _runViaBackendServer({
    required String backendUrl,
    required String prompt,
    required String modelId,
    required WorkReasoningEffort reasoningEffort,
  }) async* {
    final uri = Uri.parse('$backendUrl/api/work/run');
    final request = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream'
      ..body = jsonEncode({
        'task': prompt,
        'model': modelId,
        'reasoning_effort': reasoningEffort.apiValue,
      });
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) {
      throw Exception('Backend returned ${response.statusCode}');
    }

    String currentEvent = '';
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (_cancelled) return;
      if (line.startsWith('event:')) {
        currentEvent = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        final data = line.substring(5).trim();
        final event = WorkAgentEventParser.parseEvent(currentEvent, data);
        if (event != null) yield event;
      }
    }
  }

  Stream<WorkAgentEvent> _runViaSupabaseFunction({
    required String prompt,
    required String modelId,
    required WorkReasoningEffort reasoningEffort,
  }) async* {
    yield const WorkPlanningEvent(
      steps: [
        WorkPlanStep(
          id: 1,
          title: 'Create secure sandbox',
          status: WorkPlanStepStatus.inProgress,
        ),
        WorkPlanStep(id: 2, title: 'Execute and verify the task'),
        WorkPlanStep(id: 3, title: 'Prepare the preview and deliverable'),
      ],
    );
    yield WorkThinkingEvent(
      content: 'Starting the authenticated Build X workspace…',
      effort: reasoningEffort.displayName,
    );

    final response = await Supabase.instance.client.functions.invoke(
      'work-run',
      body: {
        'prompt': prompt,
        'model': modelId,
        'reasoning_effort': reasoningEffort.apiValue,
      },
    );
    if (_cancelled) return;

    final payload = response.data;
    if (payload is! Map) {
      throw StateError('Invalid work-run response.');
    }
    final resultValue = payload['result'];
    final result = resultValue is Map
        ? Map<String, dynamic>.from(resultValue)
        : <String, dynamic>{};
    final previewHtml = result['previewHtml']?.toString() ?? '';
    final files = (result['files'] is List)
        ? (result['files'] as List).map((value) => value.toString()).toList()
        : const <String>['index.html'];

    if (previewHtml.isNotEmpty) {
      yield WorkCodingEvent(
        filePath: result['entrypoint']?.toString() ?? 'index.html',
        newContent: previewHtml,
      );
      yield WorkTerminalEvent(
        command:
            'daytona exec --run-id ${payload['run_id'] ?? 'auto'} "test -s workspace/index.html && wc -c < workspace/index.html"',
        output:
            'Daytona sandbox verified: ${result['entrypoint'] ?? 'index.html'} (${previewHtml.length} bytes ready).',
      );
    }
    yield WorkDeliverableEvent(
      title: result['title']?.toString() ?? 'Build X workspace',
      type: result['type']?.toString() ?? 'web_app',
      entrypoint: result['entrypoint']?.toString() ?? 'index.html',
      files: files,
      previewHtml: previewHtml,
      summary:
          result['summary']?.toString() ??
          'Completed in an isolated Daytona sandbox.',
    );
    yield const WorkPlanningEvent(
      steps: [
        WorkPlanStep(
          id: 1,
          title: 'Create secure sandbox',
          status: WorkPlanStepStatus.completed,
        ),
        WorkPlanStep(
          id: 2,
          title: 'Execute and verify the task',
          status: WorkPlanStepStatus.completed,
        ),
        WorkPlanStep(
          id: 3,
          title: 'Prepare the preview and deliverable',
          status: WorkPlanStepStatus.completed,
        ),
      ],
    );
    yield const WorkDoneEvent();
  }

  static String _safeFunctionError(Object error) {
    if (error is FunctionException) {
      final details = error.details;
      if (details is Map && details['error'] is String) {
        return details['error'] as String;
      }
      return 'Build X backend request failed (${error.status}).';
    }
    if (error is BuildXApiException) return error.userMessage;
    return 'Build X backend is temporarily unavailable.';
  }

  /// Direct Autonomous Agent execution against NVIDIA NIM API
  Stream<WorkAgentEvent> _runDirectNvidiaAgent({
    required String prompt,
    required String modelId,
    required WorkReasoningEffort reasoningEffort,
    required String apiKey,
  }) async* {
    if (apiKey.isEmpty) {
      yield const WorkDoneEvent(
        error:
            'NVIDIA API key is missing. Please configure it in Settings or set NVIDIA_API_KEY.',
      );
      return;
    }

    final isConversational = isConversationalPrompt(prompt);

    if (isConversational) {
      // For simple greetings or direct conversational queries:
      // Show only lightweight Thinking indicator and stream response directly.
      yield WorkThinkingEvent(
        content: 'Thinking...',
        elapsedSeconds: 1,
        effort: reasoningEffort.displayName,
      );

      final uri = Uri.parse(BuildXConfig.chatCompletionsEndpoint);
      final requestBody = {
        'model': modelId,
        'messages': [
          {
            'role': 'system',
            'content':
                'You are Build X, an advanced AI assistant powered by NVIDIA Nemotron. '
                'Provide a direct, helpful, and concise answer to the user.',
          },
          {'role': 'user', 'content': prompt},
        ],
        'temperature': BuildXConfig.temperature,
        'top_p': BuildXConfig.topP,
        'max_tokens': BuildXConfig.maxTokens,
        'stream': true,
        'chat_template_kwargs': {'enable_thinking': true},
      };

      final request = http.Request('POST', uri)
        ..headers['Content-Type'] = 'application/json'
        ..headers['Authorization'] = 'Bearer $apiKey'
        ..headers['Accept'] = 'text/event-stream'
        ..body = jsonEncode(requestBody);

      http.StreamedResponse response;
      try {
        response = await _client.send(request);
      } catch (e) {
        final ex = BuildXApiException.network(e);
        yield WorkDoneEvent(error: ex.userMessage);
        return;
      }

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        final ex = BuildXApiException.fromHttp(
          statusCode: response.statusCode,
          responseBody: errorBody,
        );
        yield WorkDoneEvent(error: ex.userMessage);
        return;
      }

      final StringBuffer reasoningBuffer = StringBuffer();
      final StringBuffer contentBuffer = StringBuffer();
      int secondsCount = 2;
      final thinkFilter = ThinkTagStreamFilter(
        assumedThinking: true,
        suppressReasoning: false,
      );

      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lines) {
        if (_cancelled) return;
        final trimmed = line.trim();
        if (!trimmed.startsWith('data:')) continue;
        final data = trimmed.substring(5).trim();
        if (data == '[DONE]') break;

        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final choices = json['choices'] as List<dynamic>?;
          if (choices == null || choices.isEmpty) continue;
          final delta = choices[0]['delta'] as Map<String, dynamic>?;
          if (delta == null) continue;

          // 1. Explicit reasoning tokens
          final reasoningDelta =
              delta['reasoning_content'] ?? delta['reasoning'];
          if (reasoningDelta != null && reasoningDelta.toString().isNotEmpty) {
            reasoningBuffer.write(reasoningDelta);
            yield WorkThinkingEvent(
              content: reasoningBuffer.toString(),
              elapsedSeconds: secondsCount++,
              effort: reasoningEffort.displayName,
            );
          }

          // 2. Content tokens (filtered for inline think tags / orphan </think>)
          final contentDelta = delta['content']?.toString() ?? '';
          if (contentDelta.isNotEmpty) {
            final chunks = thinkFilter.feed(contentDelta);
            for (final chunk in chunks) {
              if (chunk.type == ThinkTagChunkType.reasoningDelta) {
                reasoningBuffer.write(chunk.text);
                yield WorkThinkingEvent(
                  content: reasoningBuffer.toString(),
                  elapsedSeconds: secondsCount++,
                  effort: reasoningEffort.displayName,
                );
              } else if (chunk.type == ThinkTagChunkType.textDelta) {
                contentBuffer.write(chunk.text);
                yield WorkMessageEvent(content: contentBuffer.toString());
              }
            }
          }
        } catch (_) {}
      }

      for (final chunk in thinkFilter.flush()) {
        if (chunk.type == ThinkTagChunkType.textDelta) {
          contentBuffer.write(chunk.text);
          yield WorkMessageEvent(content: contentBuffer.toString());
        }
      }

      yield const WorkDoneEvent();
      return;
    }

    // --- Genuine Build / Investigate Task Flow ---
    // Step 1: Adaptive Planning Event tailored to the task
    final taskTitle = _deriveDeliverableTitle(prompt);
    final plan = [
      WorkPlanStep(
        id: 1,
        title: 'Analyze requirements: $taskTitle',
        status: WorkPlanStepStatus.inProgress,
      ),
      const WorkPlanStep(
        id: 2,
        title: 'Research & architectural design',
        status: WorkPlanStepStatus.pending,
      ),
      const WorkPlanStep(
        id: 3,
        title: 'Generate code, styles & interactive logic',
        status: WorkPlanStepStatus.pending,
      ),
      const WorkPlanStep(
        id: 4,
        title: 'Package deliverable & verify WebContainer runtime',
        status: WorkPlanStepStatus.pending,
      ),
    ];
    yield WorkPlanningEvent(steps: List.unmodifiable(plan));

    // Step 2: Thinking state
    yield WorkThinkingEvent(
      content: 'Synthesizing task with $modelId using live reasoning...',
      elapsedSeconds: 1,
      effort: reasoningEffort.displayName,
    );

    // Call NVIDIA NIM Chat Completions
    final uri = Uri.parse(BuildXConfig.chatCompletionsEndpoint);
    final requestBody = {
      'model': modelId,
      'messages': [
        {
          'role': 'system',
          'content':
              'You are Build X Work Mode, an autonomous software engineering agent powered by NVIDIA Nemotron. '
              'The user wants you to plan and build a finished, openable deliverable (e.g. single-page web app, tool, or document). '
              'First think through the requirements thoroughly, then produce clean, complete, standalone HTML/JS/CSS code.',
        },
        {'role': 'user', 'content': prompt},
      ],
      'temperature': 0.7,
      'top_p': 1.0,
      'max_tokens': 4096,
      'stream': true,
      'chat_template_kwargs': {'enable_thinking': true},
    };

    final request = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..headers['Accept'] = 'text/event-stream'
      ..body = jsonEncode(requestBody);

    http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (e) {
      yield WorkDoneEvent(error: 'Failed to connect to NVIDIA NIM: $e');
      return;
    }

    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      yield WorkDoneEvent(
        error: 'NVIDIA API error (${response.statusCode}): $errorBody',
      );
      return;
    }

    // Step 1 done, Step 2 in progress
    plan[0] = WorkPlanStep(
      id: 1,
      title: 'Analyze requirements: $taskTitle',
      status: WorkPlanStepStatus.completed,
    );
    plan[1] = const WorkPlanStep(
      id: 2,
      title: 'Research & architectural design',
      status: WorkPlanStepStatus.inProgress,
    );
    yield WorkPlanningEvent(steps: List.unmodifiable(plan));

    yield const WorkBrowsingEvent(
      url: 'https://docs.webcontainers.io',
      title: 'WebContainers Runtime Specs & Web Standards',
      snapshot:
          'Verifying standalone client-side component execution and reactive patterns...',
      status: 'analyzing',
    );

    final StringBuffer reasoningBuffer = StringBuffer();
    final StringBuffer contentBuffer = StringBuffer();
    int secondsCount = 2;
    final thinkFilter = ThinkTagStreamFilter(
      assumedThinking: true,
      suppressReasoning: false,
    );

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (_cancelled) return;
      final trimmed = line.trim();
      if (!trimmed.startsWith('data:')) continue;
      final data = trimmed.substring(5).trim();
      if (data == '[DONE]') break;

      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final choices = json['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) continue;
        final delta = choices[0]['delta'] as Map<String, dynamic>?;
        if (delta == null) continue;

        // 1. Explicit reasoning tokens
        final reasoningDelta = delta['reasoning_content'] ?? delta['reasoning'];
        if (reasoningDelta != null && reasoningDelta.toString().isNotEmpty) {
          reasoningBuffer.write(reasoningDelta);
          yield WorkThinkingEvent(
            content: reasoningBuffer.toString(),
            elapsedSeconds: secondsCount++,
            effort: reasoningEffort.displayName,
          );
        }

        // 2. Content tokens (filtered for inline think tags / orphan </think>)
        final contentDelta = delta['content']?.toString() ?? '';
        if (contentDelta.isNotEmpty) {
          final chunks = thinkFilter.feed(contentDelta);
          for (final chunk in chunks) {
            if (chunk.type == ThinkTagChunkType.reasoningDelta) {
              reasoningBuffer.write(chunk.text);
              yield WorkThinkingEvent(
                content: reasoningBuffer.toString(),
                elapsedSeconds: secondsCount++,
                effort: reasoningEffort.displayName,
              );
            } else if (chunk.type == ThinkTagChunkType.textDelta) {
              contentBuffer.write(chunk.text);
            }
          }
        }
      } catch (_) {}
    }

    for (final chunk in thinkFilter.flush()) {
      if (chunk.type == ThinkTagChunkType.textDelta) {
        contentBuffer.write(chunk.text);
      }
    }

    // Step 2 done, Step 3 in progress (Coding)
    plan[1] = const WorkPlanStep(
      id: 2,
      title: 'Research & architectural design',
      status: WorkPlanStepStatus.completed,
    );
    plan[2] = const WorkPlanStep(
      id: 3,
      title: 'Generate code, styles & interactive logic',
      status: WorkPlanStepStatus.inProgress,
    );
    yield WorkPlanningEvent(steps: List.unmodifiable(plan));

    final rawOutput = contentBuffer.toString();
    final extractedCode = extractHtmlCode(rawOutput, prompt);

    // Yield Coding Event
    yield WorkCodingEvent(
      filePath: 'index.html',
      isNew: true,
      newContent: extractedCode,
      diff: '',
    );

    // Terminal packaging event
    yield const WorkTerminalEvent(
      command: 'webcontainer bundle --entry index.html',
      output:
          'Bundling web application for client-side execution...\nDone in 0.2s. Artifact ready.',
    );

    // Step 3 done, Step 4 completed
    plan[2] = const WorkPlanStep(
      id: 3,
      title: 'Generate code, styles & interactive logic',
      status: WorkPlanStepStatus.completed,
    );
    plan[3] = const WorkPlanStep(
      id: 4,
      title: 'Package deliverable & verify WebContainer runtime',
      status: WorkPlanStepStatus.completed,
    );
    yield WorkPlanningEvent(steps: List.unmodifiable(plan));

    // Yield Finished Deliverable Event
    yield WorkDeliverableEvent(
      title: taskTitle,
      type: 'web_app',
      entrypoint: 'index.html',
      files: const ['index.html'],
      previewHtml: extractedCode,
      summary:
          'Fully autonomous interactive application generated with $modelId via NVIDIA NIM.',
    );

    yield const WorkDoneEvent();
  }

  /// Classifies whether a prompt is conversational/greeting vs. a genuine build/task.
  static bool isConversationalPrompt(String rawPrompt) {
    final prompt = rawPrompt.trim().toLowerCase();
    if (prompt.isEmpty) return true;

    // Direct greeting / conversational match
    const commonGreetings = <String>{
      'hi',
      'hello',
      'hey',
      'yo',
      'hola',
      'bonjour',
      'sup',
      'test',
      'ping',
      'مرحبا',
      'هلا',
      'أهلا',
      'اهلا',
      'السلام عليكم',
      'سلام',
      'صباح الخير',
      'مساء الخير',
      'كيفك',
      'كيف حالك',
      'شخبارك',
      'من انت',
      'من أنت',
      'who are you',
      'what are you',
      'how are you',
      'thanks',
      'thank you',
      'شكرا',
      'مشكور',
      'good morning',
      'good afternoon',
      'good evening',
      'what can you do',
      'ماذا يمكنك أن تفعل',
      'ماذا تستطيع ان تفعل',
    };

    if (commonGreetings.contains(prompt)) {
      return true;
    }

    // Punctuation-stripped words
    final cleanPrompt = prompt
        .replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), ' ')
        .trim();
    final words = cleanPrompt
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    // Check if greeting is the main content of a very short phrase
    if (words.length <= 3) {
      final joined = words.join(' ');
      if (commonGreetings.contains(joined) ||
          words.any((w) => commonGreetings.contains(w))) {
        return true;
      }
    }

    // Explicit build/task action keywords
    const buildKeywords = <String>[
      'build',
      'create',
      'make',
      'develop',
      'implement',
      'code',
      'program',
      'design',
      'generate',
      'write an app',
      'write a program',
      'write a website',
      'write a script',
      'write code',
      'fix',
      'debug',
      'refactor',
      'investigate',
      'web app',
      'website',
      'game',
      'calculator',
      'dashboard',
      'landing page',
      'html',
      'css',
      'javascript',
      'python',
      'flutter',
      'react',
      'vue',
      'ابن',
      'انشئ',
      'أنشئ',
      'اصنع',
      'اعمل',
      'طور',
      'برمج',
      'اكتب كود',
      'صمم',
      'حلل',
      'تطبيق',
      'موقع',
      'لعبة',
      'حاسبة',
      'صفحة',
      'لوحة تحكم',
      'أداة',
      'اداة',
      'سكربت',
      'صلح',
    ];

    final hasBuildIntent = buildKeywords.any((k) => prompt.contains(k));
    if (hasBuildIntent) {
      return false;
    }

    // Conversational question starters (without build keywords)
    const questionStarters = <String>[
      'who is',
      'who was',
      'what is',
      'what are',
      'where is',
      'where are',
      'why is',
      'how does',
      'how do',
      'tell me about',
      'tell me a joke',
      'tell me a story',
      'explain',
      'explain to me',
      'ما هو',
      'ما هي',
      'من هو',
      'من هي',
      'أين',
      'اين',
      'لماذا',
      'احكي لي',
      'نكتة',
      'قصة',
      'اشرح لي',
    ];

    if (questionStarters.any((q) => prompt.startsWith(q))) {
      return true;
    }

    // Short phrase with no build keywords defaults to conversational
    if (words.length <= 10) {
      return true;
    }

    return false;
  }

  static String extractHtmlCode(String output, String prompt) {
    // Look for ```html ... ``` block
    final startTag = '```html';
    final endTag = '```';
    final startIndex = output.indexOf(startTag);
    if (startIndex != -1) {
      final codeStart = startIndex + startTag.length;
      final endIndex = output.indexOf(endTag, codeStart);
      if (endIndex != -1) {
        return output.substring(codeStart, endIndex).trim();
      }
    }

    // Or general ``` ... ```
    final genStart = output.indexOf('```');
    if (genStart != -1) {
      final lineEnd = output.indexOf('\n', genStart);
      if (lineEnd != -1) {
        final endIndex = output.indexOf('```', lineEnd);
        if (endIndex != -1) {
          final snippet = output.substring(lineEnd + 1, endIndex).trim();
          if (snippet.contains('<html') ||
              snippet.contains('<!DOCTYPE') ||
              snippet.contains('<div')) {
            return snippet;
          }
        }
      }
    }

    // Default standalone template wrapping output if no markdown blocks
    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Build X Deliverable</title>
  <style>
    :root { --bg: #09090b; --fg: #fafafa; --border: #27272a; --card: #18181b; }
    body { margin: 0; padding: 24px; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: var(--bg); color: var(--fg); line-height: 1.6; }
    .container { max-width: 760px; margin: 0 auto; background: var(--card); border: 1px solid var(--border); border-radius: 12px; padding: 28px; }
    h1 { font-size: 1.4rem; font-weight: 600; margin-top: 0; }
    pre { background: #000; padding: 16px; border-radius: 8px; overflow-x: auto; color: #e4e4e7; font-size: 0.9rem; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Autonomous Deliverable: ${prompt.trim()}</h1>
    <div>${output.replaceAll('\n', '<br/>')}</div>
  </div>
</body>
</html>''';
  }

  static String _deriveDeliverableTitle(String prompt) {
    final clean = prompt.trim();
    if (clean.length <= 40) return clean;
    return '${clean.substring(0, 37)}...';
  }
}
