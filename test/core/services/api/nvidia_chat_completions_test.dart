import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:Kelivo/core/build_x_config.dart';
import 'package:Kelivo/core/services/api/build_x_api_exception.dart';
import 'package:Kelivo/core/services/api/providers/nvidia_chat_completions.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk.dart';
import 'package:Kelivo/core/services/build_x_secure_store.dart';

void main() {
  group('BuildXSecureStore.sanitizeApiKey', () {
    test('strips surrounding quotes', () {
      expect(
        BuildXSecureStore.sanitizeApiKey('"nvapi-test"'),
        equals('nvapi-test'),
      );
      expect(
        BuildXSecureStore.sanitizeApiKey("'nvapi-test'"),
        equals('nvapi-test'),
      );
    });

    test('strips angle brackets <...>', () {
      expect(
        BuildXSecureStore.sanitizeApiKey('<nvapi-test>'),
        equals('nvapi-test'),
      );
      expect(
        BuildXSecureStore.sanitizeApiKey('<<nvapi-test>>'),
        equals('nvapi-test'),
      );
    });

    test('strips Bearer prefix case-insensitively and repeatedly', () {
      expect(
        BuildXSecureStore.sanitizeApiKey('Bearer nvapi-test'),
        equals('nvapi-test'),
      );
      expect(
        BuildXSecureStore.sanitizeApiKey('bearer nvapi-test'),
        equals('nvapi-test'),
      );
      expect(
        BuildXSecureStore.sanitizeApiKey('Bearer Bearer nvapi-test'),
        equals('nvapi-test'),
      );
      expect(
        BuildXSecureStore.sanitizeApiKey('Bearer <nvapi-test>'),
        equals('nvapi-test'),
      );
    });

    test('strips newlines and trailing/leading whitespace', () {
      expect(
        BuildXSecureStore.sanitizeApiKey("  nvapi-test \r\n "),
        equals('nvapi-test'),
      );
    });
  });

  group('BuildXApiException', () {
    test('maps 401 to a clear authentication error', () {
      final ex = BuildXApiException.fromHttp(
        statusCode: 401,
        responseBody: '{"detail":"Auth failed"}',
      );
      expect(ex.userMessage, equals('The AI service could not authenticate.'));
      expect(ex.statusCode, equals(401));
    });

    test('maps 429 to a clear rate limit error', () {
      final ex = BuildXApiException.fromHttp(statusCode: 429);
      expect(
        ex.userMessage,
        equals('The AI service is busy (HTTP 429). Please retry shortly.'),
      );
      expect(ex.statusCode, equals(429));
    });

    test('maps 500-504 to clear server error messages', () {
      final ex500 = BuildXApiException.fromHttp(statusCode: 500);
      expect(
        ex500.userMessage,
        equals('The AI service returned HTTP 500. Please retry later.'),
      );
      final ex503 = BuildXApiException.fromHttp(statusCode: 503);
      expect(
        ex503.userMessage,
        equals('The AI service returned HTTP 503. Please retry later.'),
      );
    });

    test('maps network errors to a clear connection error message', () {
      final ex = BuildXApiException.network('Connection refused');
      expect(
        ex.userMessage,
        equals(
          'Could not connect to the AI service. Check your network and retry.',
        ),
      );
    });
  });

  group('NvidiaChatCompletions.decodeEvents', () {
    test('parses delta.content and terminates on [DONE]', () async {
      final sseStream = Stream.fromIterable([
        utf8.encode('data: {"choices":[{"delta":{"content":"Hello"}}]}\n\n'),
        utf8.encode('data: {"choices":[{"delta":{"content":" world!"}}]}\n\n'),
        utf8.encode('data: [DONE]\n\n'),
      ]);

      final events = await NvidiaChatCompletions.decodeEvents(
        sseStream,
      ).toList();
      expect(events.length, equals(2));
      expect(events[0]['choices'][0]['delta']['content'], equals('Hello'));
      expect(events[1]['choices'][0]['delta']['content'], equals(' world!'));
    });

    test('safely skips malformed lines and empty choices', () async {
      final sseStream = Stream.fromIterable([
        utf8.encode('random invalid text\n'),
        utf8.encode('data: not json\n\n'),
        utf8.encode('data: {"choices":[]}\n\n'),
        utf8.encode('data: {"choices":[{"delta":{"content":"ok"}}]}\n\n'),
        utf8.encode('data: [DONE]\n\n'),
      ]);

      final events = await NvidiaChatCompletions.decodeEvents(
        sseStream,
      ).toList();
      expect(events.length, equals(2));
      expect(events[0]['choices'], isEmpty);
      expect(events[1]['choices'][0]['delta']['content'], equals('ok'));
    });
  });

  group('NvidiaChatCompletions.send with MockClient', () {
    test('sends correct headers and handles streaming chunks', () async {
      final mockClient = MockClient.streaming((request, bodyStream) async {
        expect(
          request.url.toString(),
          equals(BuildXConfig.chatCompletionsEndpoint),
        );
        expect(
          request.headers['Authorization'],
          equals('Bearer nvapi-valid-key'),
        );
        expect(request.headers['Content-Type'], equals('application/json'));
        expect(request.headers['Accept'], equals('text/event-stream'));

        final body =
            jsonDecode(await bodyStream.bytesToString())
                as Map<String, dynamic>;
        expect(body['model'], equals(BuildXConfig.chatModelId));
        expect(body['stream'], isTrue);
        expect(body['temperature'], equals(BuildXConfig.chatTemperature));
        expect(body['top_p'], equals(BuildXConfig.chatTopP));
        expect(body['max_tokens'], equals(BuildXConfig.chatMaxTokens));
        expect(body['reasoning_effort'], equals('max'));
        expect(body['chat_template_kwargs'], equals({'clear_thinking': true}));

        final sseData = [
          'data: {"choices":[{"delta":{"reasoning_content":"Thinking..."}}]}\n\n',
          'data: {"choices":[{"delta":{"content":"Answer!"}}]}\n\n',
          'data: {"choices":[{"finish_reason":"stop"}]}\n\n',
          'data: [DONE]\n\n',
        ].join();

        return http.StreamedResponse(Stream.value(utf8.encode(sseData)), 200);
      });

      final chunks = await NvidiaChatCompletions.send(
        client: mockClient,
        messages: [
          {'role': 'user', 'content': 'Test prompt'},
        ],
        apiKeyOverride: '<nvapi-valid-key>',
        suppressReasoning: true,
      ).toList();

      expect(chunks.any((c) => c is TextStart), isTrue);
      expect(chunks.any((c) => c is TextDelta && c.text == 'Answer!'), isTrue);
      expect(chunks.any((c) => c is Finish), isTrue);
    });

    test('throws BuildXApiException with a clear message on 401', () async {
      final mockClient = MockClient.streaming((request, _) async {
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              '{"status":401,"title":"Unauthorized","detail":"Authentication failed"}',
            ),
          ),
          401,
        );
      });

      expect(
        () => NvidiaChatCompletions.send(
          client: mockClient,
          messages: [
            {'role': 'user', 'content': 'Hi'},
          ],
          apiKeyOverride: 'nvapi-bad-key',
        ).drain(),
        throwsA(
          isA<BuildXApiException>().having(
            (e) => e.userMessage,
            'userMessage',
            'The AI service could not authenticate.',
          ),
        ),
      );
    });
  });
}
