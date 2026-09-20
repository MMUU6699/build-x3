import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Kelivo/core/services/api/providers/mistral_conversations.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'SSE frames survive arbitrary byte boundaries and event names',
    () async {
      final frames = <Map<String, dynamic>>[];
      final source =
          'event: message.output.delta\n'
          'data: {"content":"café"}\n\n'
          'data: [DONE]\n\n';
      final bytes = utf8.encode(source);
      await for (final frame in MistralConversations.decodeEvents(
        Stream.fromIterable(bytes.map((byte) => <int>[byte])),
      )) {
        frames.add(frame);
      }
      expect(frames, [
        {'type': 'message.output.delta', 'content': 'café'},
      ]);
    },
  );

  test('subsequent turns append to the stored remote conversation', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <http.Request>[];
    var count = 0;
    final client = MockClient((request) async {
      requests.add(request);
      count++;
      final id = count == 1 ? 'remote-first' : 'remote-second';
      final frames = [
        {'type': 'conversation.response.started', 'conversation_id': id},
        {'type': 'message.output.delta', 'content': 'reply $count'},
        {'type': 'conversation.response.done', 'conversation_id': id},
      ];
      return http.Response(
        frames.map((event) => 'data: ${jsonEncode(event)}\n\n').join(),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });

    final first = await MistralConversations.send(
      client: client,
      messages: [
        {'role': 'system', 'content': 'Be concise.'},
        {'role': 'user', 'content': 'Hello'},
      ],
      localConversationId: 'local-chat',
      apiKeyOverride: 'test-key',
    ).toList();
    final second = await MistralConversations.send(
      client: client,
      messages: [
        {'role': 'system', 'content': 'Be helpful now.'},
        {'role': 'user', 'content': 'Hello'},
        {'role': 'assistant', 'content': 'reply 1'},
        {'role': 'user', 'content': 'Again'},
      ],
      localConversationId: 'local-chat',
      apiKeyOverride: 'test-key',
    ).toList();

    expect(requests[0].url.path, '/v1/conversations');
    expect(requests[1].url.path, '/v1/conversations/remote-first');
    final start = jsonDecode(requests[0].body) as Map<String, dynamic>;
    final append = jsonDecode(requests[1].body) as Map<String, dynamic>;
    expect(start['model'], 'mistral-medium-latest');
    expect(start['instructions'], 'Be concise.');
    expect(start['completion_args'], {
      'temperature': 0.7,
      'max_tokens': 2048,
      'top_p': 1.0,
    });
    expect(append['inputs'], 'Again');
    expect(append.containsKey('instructions'), isFalse);
    expect(append.containsKey('model'), isFalse);
    expect(first.whereType<TextDelta>().single.text, 'reply 1');
    expect(second.whereType<TextDelta>().single.text, 'reply 2');
    client.close();
  });

  test('function call results are appended to the same conversation', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      final events = requests.length == 1
          ? [
              {
                'type': 'conversation.response.started',
                'conversation_id': 'remote-tool',
              },
              {
                'type': 'conversation.response.done',
                'conversation_id': 'remote-tool',
                'outputs': [
                  {
                    'type': 'function.call',
                    'tool_call_id': 'call-1',
                    'name': 'lookup',
                    'arguments': '{"term":"hello"}',
                  },
                ],
              },
            ]
          : [
              {'type': 'message.output.delta', 'content': 'Found it.'},
              {
                'type': 'conversation.response.done',
                'conversation_id': 'remote-final',
              },
            ];
      return http.Response(
        events.map((event) => 'data: ${jsonEncode(event)}\n\n').join(),
        200,
      );
    });
    final chunks = await MistralConversations.send(
      client: client,
      messages: [
        {'role': 'user', 'content': 'Look up hello'},
      ],
      localConversationId: 'tool-chat',
      apiKeyOverride: 'test-key',
      tools: [
        {
          'type': 'function',
          'function': {'name': 'lookup'},
        },
      ],
      onToolCall: (name, args, {toolCallId}) async {
        expect(name, 'lookup');
        expect(args, {'term': 'hello'});
        expect(toolCallId, 'call-1');
        return {'answer': 42};
      },
    ).toList();
    expect(requests.length, 2);
    final first = jsonDecode(requests[0].body) as Map<String, dynamic>;
    final followUp = jsonDecode(requests[1].body) as Map<String, dynamic>;
    expect(first['tools'], isNotEmpty);
    expect(requests[1].url.path, '/v1/conversations/remote-tool');
    expect(followUp['inputs'], [
      {
        'type': 'function.result',
        'tool_call_id': 'call-1',
        'result': '{"answer":42}',
      },
    ]);
    expect(chunks.whereType<ToolCallResult>().single.output, {'answer': 42});
    expect(chunks.whereType<TextDelta>().single.text, 'Found it.');
    client.close();
  });
}
