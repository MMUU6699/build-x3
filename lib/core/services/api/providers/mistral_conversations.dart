import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../build_x_config.dart';
import '../../build_x_secure_store.dart';
import '../chat_api_helpers.dart' show ToolCallHandler;
import '../stream/stream_chunk.dart';

/// Dedicated adapter for Mistral's stateful Conversations API.
///
/// `#stream` in the API reference names the streaming operation. URL fragments
/// are not transmitted by HTTP, so the wire request uses the same path with
/// `stream: true` and `Accept: text/event-stream`.
abstract final class MistralConversations {
  static Future<String?> _remoteId(String localId, String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_storageKey(localId, apiKey));
  }

  static Future<void> _saveRemoteId(
    String localId,
    String apiKey,
    String remoteId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey(localId, apiKey), remoteId);
  }

  static String _storageKey(String localId, String apiKey) {
    final fingerprint = sha256.convert(utf8.encode(apiKey)).toString();
    return 'build_x_conversation:$fingerprint:$localId';
  }

  static Stream<StreamChunk> send({
    required http.Client client,
    required List<Map<String, dynamic>> messages,
    String? localConversationId,
    bool persistConversation = true,
    String? apiKeyOverride,
    List<Map<String, dynamic>>? tools,
    ToolCallHandler? onToolCall,
  }) async* {
    final apiKey = apiKeyOverride ?? await BuildXSecureStore.readMistralKey();
    if (apiKey.isEmpty) {
      throw StateError('Add a Mistral API key in Build X settings first.');
    }

    final localId = localConversationId?.trim();
    final remoteId =
        persistConversation && localId != null && localId.isNotEmpty
        ? await _remoteId(localId, apiKey)
        : null;
    String? currentRemoteId = remoteId;
    Object inputs = currentRemoteId == null
        ? _initialInputs(messages)
        : _lastUserInput(messages);
    yield const TextStart('mistral-text');
    for (var round = 0; round < 8; round++) {
      final isAppend = currentRemoteId != null && currentRemoteId.isNotEmpty;
      final uri = Uri.parse(
        isAppend
            ? '${BuildXConfig.apiBase}/$currentRemoteId'
            : BuildXConfig.apiBase,
      );
      final request = http.Request('POST', uri)
        ..headers.addAll({
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
        })
        ..body = jsonEncode({
          if (!isAppend) 'model': BuildXConfig.modelId,
          'inputs': inputs,
          if (!isAppend && _instructions(messages).isNotEmpty)
            'instructions': _instructions(messages),
          if (!isAppend && tools != null && tools.isNotEmpty) 'tools': tools,
          'completion_args': const {
            'temperature': BuildXConfig.temperature,
            'max_tokens': BuildXConfig.maxTokens,
            'top_p': BuildXConfig.topP,
          },
          'store': true,
          'stream': true,
        });
      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.drain<void>();
        throw StateError(
          'Mistral request failed (HTTP ${response.statusCode}).',
        );
      }

      var completed = false;
      var emittedThisResponse = false;
      final calls = <String, Map<String, dynamic>>{};
      await for (final event in decodeEvents(response.stream)) {
        final type = event['type']?.toString() ?? '';
        switch (type) {
          case 'conversation.response.started':
            currentRemoteId =
                event['conversation_id']?.toString() ?? currentRemoteId;
          case 'message.output.delta':
            final text = _contentText(event['content']);
            if (text.isNotEmpty) {
              emittedThisResponse = true;
              yield TextDelta(id: 'mistral-text', text: text);
            }
          case 'function.call':
            _collectCall(calls, event);
          case 'conversation.response.done':
            currentRemoteId =
                event['conversation_id']?.toString() ?? currentRemoteId;
            final outputs = event['outputs'];
            if (outputs is List) {
              for (final output in outputs.whereType<Map>()) {
                _collectCall(calls, Map<String, dynamic>.from(output));
              }
            }
            if (!emittedThisResponse) {
              final text = _outputText(outputs);
              if (text.isNotEmpty) {
                yield TextDelta(id: 'mistral-text', text: text);
              }
            }
            completed = true;
          case 'conversation.response.error':
            throw StateError(
              'Mistral could not complete the conversation: '
              '${event['message'] ?? event['error'] ?? 'unknown error'}',
            );
        }
      }
      if (!completed) {
        throw StateError(
          'Mistral closed the stream before completing the reply.',
        );
      }
      if (calls.isEmpty) {
        if (persistConversation && localId != null && localId.isNotEmpty) {
          final id = currentRemoteId;
          if (id == null || id.isEmpty) {
            throw StateError('Mistral did not return a conversation ID.');
          }
          await _saveRemoteId(localId, apiKey, id);
        }
        yield const TextEnd('mistral-text');
        return;
      }
      if (onToolCall == null || currentRemoteId == null) {
        throw StateError('Mistral requested a tool that is unavailable.');
      }
      final results = <Map<String, String>>[];
      for (final call in calls.values) {
        final id = call['tool_call_id']?.toString() ?? '';
        final name = call['name']?.toString() ?? '';
        if (id.isEmpty || name.isEmpty) {
          throw StateError('Mistral returned an incomplete tool call.');
        }
        final rawArgs = call['arguments'];
        final decodedArgs = rawArgs is String ? jsonDecode(rawArgs) : rawArgs;
        if (decodedArgs is! Map) {
          throw StateError('Mistral returned invalid tool arguments.');
        }
        yield ToolCallStart(id: id, toolName: name);
        yield ToolCallEnd(id);
        final output = await onToolCall(
          name,
          Map<String, dynamic>.from(decodedArgs),
          toolCallId: id,
        );
        yield ToolCallResult(id: id, output: output);
        results.add({
          'type': 'function.result',
          'tool_call_id': id,
          'result': output is String ? output : jsonEncode(output),
        });
      }
      inputs = results;
    }
    throw StateError('Mistral exceeded the tool-call limit.');
  }

  static void _collectCall(
    Map<String, Map<String, dynamic>> calls,
    Map<String, dynamic> event,
  ) {
    if (event['type'] != 'function.call') return;
    final id = event['tool_call_id']?.toString() ?? '';
    if (id.isNotEmpty) calls[id] = event;
  }

  static Object _lastUserInput(List<Map<String, dynamic>> messages) {
    for (final message in messages.reversed) {
      if (message['role'] == 'user') {
        return _contentText(message['content']);
      }
    }
    throw StateError('No user message was available for Mistral.');
  }

  static Object _initialInputs(List<Map<String, dynamic>> messages) {
    final inputs = <Map<String, String>>[];
    for (final message in messages) {
      final role = message['role']?.toString();
      if (role != 'user' && role != 'assistant') continue;
      final content = _contentText(message['content']);
      if (content.isNotEmpty) inputs.add({'role': role!, 'content': content});
    }
    if (inputs.isEmpty) {
      throw StateError('No user message was available for Mistral.');
    }
    return inputs;
  }

  static String _instructions(List<Map<String, dynamic>> messages) => messages
      .where(
        (message) =>
            message['role'] == 'system' || message['role'] == 'developer',
      )
      .map((message) => _contentText(message['content']))
      .where((text) => text.isNotEmpty)
      .join('\n\n');

  static String _outputText(Object? value) {
    if (value is! List) return '';
    return value
        .whereType<Map>()
        .where((entry) => entry['type'] == 'message.output')
        .map((entry) => _contentText(entry['content']))
        .join();
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

  /// Parses SSE frames independently of the HTTP transport and chunk sizes.
  static Stream<Map<String, dynamic>> decodeEvents(
    Stream<List<int>> bytes,
  ) async* {
    final data = StringBuffer();
    String? eventName;
    await for (final line
        in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isEmpty) {
        if (data.isNotEmpty) {
          final raw = data.toString().trim();
          if (raw != '[DONE]') {
            final decoded = jsonDecode(raw);
            if (decoded is Map<String, dynamic>) {
              if (decoded['type'] == null && eventName != null) {
                decoded['type'] = eventName;
              }
              yield decoded;
            }
          }
        }
        data.clear();
        eventName = null;
        continue;
      }
      if (line.startsWith('event:')) {
        eventName = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        if (data.isNotEmpty) data.write('\n');
        data.write(line.substring(5).trimLeft());
      }
    }
    if (data.isNotEmpty) {
      final raw = data.toString().trim();
      if (raw != '[DONE]') {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          if (decoded['type'] == null && eventName != null) {
            decoded['type'] = eventName;
          }
          yield decoded;
        }
      }
    }
  }
}
