import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../work_mode_config.dart';
import '../api/build_x_api_exception.dart';
import '../build_x_secure_store.dart';
import 'work_agent_event.dart';

/// Execution service for Build X Work Mode.
///
/// Connects to the authenticated Build X Work backend and streams its
/// persisted Plan-Act execution events. Work Mode does not fabricate local
/// browser, shell, or deliverable events when the hosted runtime is absent.
class WorkAgentService {
  WorkAgentService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  bool _cancelled = false;
  String? _activeRunId;

  String? get activeRunId => _activeRunId;

  void cancel() {
    _cancelled = true;
  }

  Future<WorkAgentEvent?> controlBrowser({
    required String runId,
    required String action,
    double? x,
    double? y,
    String? key,
    String? code,
    String? text,
    String? direction,
  }) async {
    final response = await Supabase.instance.client.functions.invoke(
      'work-control',
      body: {
        'run_id': runId,
        'action': action,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
        if (key != null) 'key': key,
        if (code != null) 'code': code,
        if (text != null) 'text': text,
        if (direction != null) 'direction': direction,
      },
    );
    final data = response.data;
    if (data is! Map) return null;
    final payload = Map<String, dynamic>.from(data);
    return WorkAgentEventParser.parseEvent(
      'computer',
      jsonEncode({
        'action': payload['action'] ?? 'Browser control',
        'screenshot_base64': payload['screenshot_base64'] ?? '',
        'url': payload['url'] ?? '',
        'title': payload['title'] ?? '',
      }),
    );
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
    final backendUrl = customBackendUrl?.trim().isNotEmpty == true
        ? customBackendUrl!.trim()
        : await BuildXSecureStore.readWorkBackendUrl();

    // 1. Production path: Supabase Edge Function orchestration with Daytona sandbox.
    try {
      yield* _runViaSupabaseFunction(
        prompt: prompt,
        modelId: modelId,
        reasoningEffort: reasoningEffort,
      );
      return;
    } catch (error) {
      debugPrint('[WorkAgentService] Supabase function error: $error');
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

    // A direct client-side fallback cannot prove browser or terminal work and
    // must never fabricate Work events. BYOK remains available to Chat mode;
    // Work mode reports the backend failure explicitly.
    yield WorkDoneEvent(
      error:
          'Work backend unavailable. Sign in and retry after the Work runtime is reachable.',
    );
  }

  /// Connects to Build X Work backend server via SSE
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
    final runId = const Uuid().v4();
    _activeRunId = runId;
    final client = Supabase.instance.client;
    final events = StreamController<WorkAgentEvent>.broadcast();
    final ready = Completer<void>();
    var gotTerminalEvent = false;
    final seenSequences = <int>{};
    void addEventRow(Map<String, dynamic> row) {
      final sequence = int.tryParse('${row['sequence']}');
      if (sequence != null && !seenSequences.add(sequence)) return;
      final type = row['event_type']?.toString() ?? '';
      final body = row['payload'];
      if (body is Map) {
        final event = WorkAgentEventParser.parseEvent(
          type,
          jsonEncode(Map<String, dynamic>.from(body)),
        );
        if (event != null && !events.isClosed) events.add(event);
        if (event is WorkDoneEvent) gotTerminalEvent = true;
      }
    }

    final channel = client
        .channel('work-run-$runId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'work_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'run_id',
            value: runId,
          ),
          callback: (payload) {
            addEventRow(Map<String, dynamic>.from(payload.newRecord));
          },
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed &&
              !ready.isCompleted) {
            ready.complete();
          } else if (status == RealtimeSubscribeStatus.channelError &&
              !ready.isCompleted) {
            ready.completeError(
              StateError('Unable to subscribe to live Work events.'),
            );
          }
        });

    try {
      await ready.future.timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint(
        '[WorkAgentService] Realtime channel ready timeout/notice: $e',
      );
    }

    // Reconnect-safe catch-up: subscribe first, then backfill rows by the
    // server sequence. The set prevents a row delivered by both paths from
    // being rendered twice.
    try {
      final rows = await client
          .from('work_events')
          .select('sequence,event_type,payload')
          .eq('run_id', runId)
          .order('sequence', ascending: true);
      for (final row in rows) {
        addEventRow(Map<String, dynamic>.from(row));
      }
    } catch (error) {
      debugPrint('[WorkAgentService] Work event catch-up notice: $error');
    }

    try {
      final invocation = client.functions.invoke(
        'work-run',
        body: {
          'run_id': runId,
          'prompt': prompt,
          'model': modelId,
          'reasoning_effort': reasoningEffort.apiValue,
        },
      );
      unawaited(
        invocation.then<void>(
          (response) {
            if (gotTerminalEvent || events.isClosed) return;
            final payload = response.data;
            if (payload is Map && payload['status'] == 'conversation') {
              final message = payload['message']?.toString().trim() ?? '';
              if (message.isNotEmpty) {
                events.add(WorkMessageEvent(content: message));
              }
              events.add(const WorkDoneEvent());
              return;
            }
            if (payload is Map && payload['status'] == 'completed') {
              final value = payload['result'];
              if (value is Map) {
                final result = Map<String, dynamic>.from(value);
                events.add(
                  WorkDeliverableEvent(
                    title: result['title']?.toString() ?? 'Build X workspace',
                    type: result['type']?.toString() ?? 'web_app',
                    entrypoint:
                        result['entrypoint']?.toString() ?? 'index.html',
                    files:
                        (result['files'] as List<dynamic>?)
                            ?.map((item) => item.toString())
                            .toList() ??
                        const ['index.html'],
                    previewHtml: result['previewHtml']?.toString() ?? '',
                    summary: 'Completed in an isolated Daytona sandbox.',
                  ),
                );
                events.add(const WorkDoneEvent());
              }
            }
            if (payload is Map && payload['status'] == 'waiting') {
              events.add(
                WorkWaitingEvent(
                  message: payload['message']?.toString() ?? '',
                  suggestUserTakeover:
                      payload['suggest_user_takeover']?.toString() ?? 'none',
                ),
              );
            }
          },
          onError: (Object error, StackTrace _) {
            if (!events.isClosed) {
              events.add(WorkDoneEvent(error: _safeFunctionError(error)));
            }
          },
        ),
      );
      await for (final event in events.stream) {
        if (_cancelled) break;
        yield event;
        if (event is WorkDoneEvent || event is WorkWaitingEvent) break;
      }
      await invocation;
    } finally {
      await client.removeChannel(channel);
      await events.close();
    }
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

  /// Classifies whether a prompt is a browser / web exploration task.
  static bool isBrowserPrompt(String rawPrompt) {
    final lower = rawPrompt.trim().toLowerCase();
    return RegExp(
      r'(browser|chrome|chromium|google|webpage|search|navigate|open|browse|متصفح|كروم|جوجل|بحث|ابحث|تصفح|صفحة|ادخل|موقع|رابط)',
      caseSensitive: false,
    ).hasMatch(lower);
  }

  /// Classifies whether a prompt is a shell / terminal command task.
  static bool isTerminalPrompt(String rawPrompt) {
    final lower = rawPrompt.trim().toLowerCase();
    return RegExp(
      r'(terminal|bash|shell|command|exec|run|cmd|script|python|linux|ubuntu|طرفية|شغل|أمر|اوامر|نفذ|بايثون)',
      caseSensitive: false,
    ).hasMatch(lower);
  }

  /// Classifies whether a prompt explicitly requests creating/building a web app or website.
  static bool isExplicitWebCreationPrompt(String rawPrompt) {
    final lower = rawPrompt.trim().toLowerCase();
    return RegExp(
      r'(build|create|make|code|design|generate|انشئ|صمم|ابن|برمج|سوي|اعمل).*(website|web app|landing page|html|dashboard|portfolio|game|snake|pomodoro|calculator|موقع|صفحة ويب|تطبيق ويب)',
      caseSensitive: false,
    ).hasMatch(lower);
  }

  /// Classifies whether a prompt is conversational/greeting vs. a genuine build/task.
  static bool isConversationalPrompt(String rawPrompt) {
    if (isBrowserPrompt(rawPrompt) ||
        isTerminalPrompt(rawPrompt) ||
        isExplicitWebCreationPrompt(rawPrompt)) {
      return false;
    }
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

    // Do not fabricate a document when the model did not return one.
    return output.trim();
  }
}
