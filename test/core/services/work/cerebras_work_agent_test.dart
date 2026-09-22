import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/work_mode_config.dart';
import 'package:Kelivo/core/services/work/work_agent_event.dart';
import 'package:Kelivo/core/services/work/work_agent_service.dart';

void main() {
  group('WorkModeConfig', () {
    test('availableModels contains consolidated Nemotron model', () {
      expect(WorkModeConfig.availableModels, contains('nvidia/nemotron-3-ultra-550b-a55b'));
      expect(WorkModeConfig.defaultModel, equals('nvidia/nemotron-3-ultra-550b-a55b'));
    });

    test('modelDisplayName and modelSubtitle format expected descriptions', () {
      expect(
        WorkModeConfig.modelDisplayName('nvidia/nemotron-3-ultra-550b-a55b'),
        equals('Nemotron 3 Ultra 550B'),
      );
      expect(WorkModeConfig.modelDisplayName('custom'), equals('custom'));

      expect(
        WorkModeConfig.modelSubtitle('nvidia/nemotron-3-ultra-550b-a55b'),
        contains('550B Reasoning & Code'),
      );
    });

    test('liteLlmModel prefixes model ID with openai/ for OpenHands SDK', () {
      expect(
        WorkModeConfig.liteLlmModel('nvidia/nemotron-3-ultra-550b-a55b'),
        equals('openai/nvidia/nemotron-3-ultra-550b-a55b'),
      );
    });
  });

  group('WorkReasoningEffort', () {
    test('parses from valid and case-insensitive strings', () {
      expect(WorkReasoningEffort.fromString('low'), equals(WorkReasoningEffort.low));
      expect(WorkReasoningEffort.fromString('LOW'), equals(WorkReasoningEffort.low));
      expect(WorkReasoningEffort.fromString('medium'), equals(WorkReasoningEffort.medium));
      expect(WorkReasoningEffort.fromString('high'), equals(WorkReasoningEffort.high));
      expect(WorkReasoningEffort.fromString('HIGH'), equals(WorkReasoningEffort.high));
      expect(WorkReasoningEffort.fromString(null), equals(WorkReasoningEffort.medium));
      expect(WorkReasoningEffort.fromString('unknown'), equals(WorkReasoningEffort.medium));
    });

    test('holds valid api values for chat completions', () {
      expect(WorkReasoningEffort.low.apiValue, equals('low'));
      expect(WorkReasoningEffort.medium.apiValue, equals('medium'));
      expect(WorkReasoningEffort.high.apiValue, equals('high'));
    });
  });

  group('WorkPlanStep & Status', () {
    test('parses status correctly', () {
      expect(WorkPlanStepStatus.fromString('in_progress'), equals(WorkPlanStepStatus.inProgress));
      expect(WorkPlanStepStatus.fromString('inprogress'), equals(WorkPlanStepStatus.inProgress));
      expect(WorkPlanStepStatus.fromString('completed'), equals(WorkPlanStepStatus.completed));
      expect(WorkPlanStepStatus.fromString('done'), equals(WorkPlanStepStatus.completed));
      expect(WorkPlanStepStatus.fromString('failed'), equals(WorkPlanStepStatus.failed));
      expect(WorkPlanStepStatus.fromString('pending'), equals(WorkPlanStepStatus.pending));
      expect(WorkPlanStepStatus.fromString(null), equals(WorkPlanStepStatus.pending));
    });

    test('serializes and deserializes step JSON', () {
      final step = WorkPlanStep(
        id: 1,
        title: 'Initialize workspace',
        status: WorkPlanStepStatus.inProgress,
      );
      final json = step.toJson();
      final fromJson = WorkPlanStep.fromJson(json);

      expect(fromJson.id, equals(1));
      expect(fromJson.title, equals('Initialize workspace'));
      expect(fromJson.status, equals(WorkPlanStepStatus.inProgress));
    });
  });

  group('WorkAgentEventParser', () {
    test('parses planning event', () {
      final data = jsonEncode({
        'steps': [
          {'id': 1, 'title': 'Design UI', 'status': 'completed'},
          {'id': 2, 'title': 'Build layout', 'status': 'in_progress'},
        ]
      });
      final event = WorkAgentEventParser.parseEvent('planning', data);
      expect(event, isA<WorkPlanningEvent>());
      final planning = event as WorkPlanningEvent;
      expect(planning.steps.length, equals(2));
      expect(planning.steps[0].status, equals(WorkPlanStepStatus.completed));
      expect(planning.steps[1].title, equals('Build layout'));
    });

    test('parses thinking event', () {
      final data = jsonEncode({
        'content': 'Analyzing the user request and considering the layout...',
        'elapsed_seconds': 4,
        'effort': 'high',
      });
      final event = WorkAgentEventParser.parseEvent('thinking', data);
      expect(event, isA<WorkThinkingEvent>());
      final thinking = event as WorkThinkingEvent;
      expect(thinking.content, contains('Analyzing'));
      expect(thinking.elapsedSeconds, equals(4));
      expect(thinking.effort, equals('high'));
    });

    test('parses browsing event', () {
      final data = jsonEncode({
        'url': 'https://pub.dev',
        'title': 'Dart packages',
        'snapshot': 'Dart package repository snapshot',
        'status': 'loaded',
      });
      final event = WorkAgentEventParser.parseEvent('browsing', data);
      expect(event, isA<WorkBrowsingEvent>());
      final browsing = event as WorkBrowsingEvent;
      expect(browsing.url, equals('https://pub.dev'));
      expect(browsing.title, equals('Dart packages'));
    });

    test('parses coding event with diff and content', () {
      final data = jsonEncode({
        'filePath': 'lib/index.html',
        'isNew': false,
        'oldContent': '<div>old</div>',
        'newContent': '<div>new</div>',
        'diff': '@@ -1,1 +1,1 @@\n-<div>old</div>\n+<div>new</div>',
      });
      final event = WorkAgentEventParser.parseEvent('coding', data);
      expect(event, isA<WorkCodingEvent>());
      final coding = event as WorkCodingEvent;
      expect(coding.filePath, equals('lib/index.html'));
      expect(coding.isNew, isFalse);
      expect(coding.diff, contains('+<div>new</div>'));
    });

    test('parses terminal event', () {
      final data = jsonEncode({
        'command': 'npm run build',
        'output': 'Build successful: bundle.js (120kb)',
      });
      final event = WorkAgentEventParser.parseEvent('terminal', data);
      expect(event, isA<WorkTerminalEvent>());
      final terminal = event as WorkTerminalEvent;
      expect(terminal.command, equals('npm run build'));
      expect(terminal.output, contains('successful'));
    });

    test('parses deliverable event with previewHtml', () {
      final data = jsonEncode({
        'title': 'Pomodoro Timer App',
        'type': 'web_app',
        'entrypoint': 'index.html',
        'files': ['index.html', 'style.css', 'app.js'],
        'previewHtml': '<html><body><h1>Pomodoro</h1></body></html>',
        'summary': 'Interactive timer application with sound alerts',
      });
      final event = WorkAgentEventParser.parseEvent('deliverable', data);
      expect(event, isA<WorkDeliverableEvent>());
      final deliverable = event as WorkDeliverableEvent;
      expect(deliverable.title, equals('Pomodoro Timer App'));
      expect(deliverable.files.length, equals(3));
      expect(deliverable.previewHtml, contains('Pomodoro'));
    });

    test('parses done event', () {
      final data = jsonEncode({'error': null});
      final event = WorkAgentEventParser.parseEvent('done', data);
      expect(event, isA<WorkDoneEvent>());
      expect((event as WorkDoneEvent).error, isNull);
    });

    test('parses message event', () {
      final data = jsonEncode({'content': 'Hello! How can I help you today?'});
      final event = WorkAgentEventParser.parseEvent('message', data);
      expect(event, isA<WorkMessageEvent>());
      expect((event as WorkMessageEvent).content, equals('Hello! How can I help you today?'));
    });

    test('returns null on invalid or empty event', () {
      expect(WorkAgentEventParser.parseEvent('unknown', '{}'), isNull);
      expect(WorkAgentEventParser.parseEvent('planning', ''), isNull);
      expect(WorkAgentEventParser.parseEvent('planning', '{broken json'), isNull);
    });
  });

  group('WorkAgentService.isConversationalPrompt', () {
    test('identifies greetings as conversational', () {
      expect(WorkAgentService.isConversationalPrompt('hello'), isTrue);
      expect(WorkAgentService.isConversationalPrompt('hi'), isTrue);
      expect(WorkAgentService.isConversationalPrompt('هلا'), isTrue);
      expect(WorkAgentService.isConversationalPrompt('مرحبا'), isTrue);
      expect(WorkAgentService.isConversationalPrompt('صباح الخير'), isTrue);
    });

    test('identifies simple queries as conversational', () {
      expect(WorkAgentService.isConversationalPrompt('who are you'), isTrue);
      expect(WorkAgentService.isConversationalPrompt('how are you today?'), isTrue);
      expect(WorkAgentService.isConversationalPrompt('ما هو الطقس اليوم؟'), isTrue);
    });

    test('identifies build and code tasks as non-conversational genuine tasks', () {
      expect(WorkAgentService.isConversationalPrompt('build a pomodoro timer app with sound'), isFalse);
      expect(WorkAgentService.isConversationalPrompt('create a modern portfolio website with html and css'), isFalse);
      expect(WorkAgentService.isConversationalPrompt('ابن لي تطبيق حاسبة تفاعلي'), isFalse);
      expect(WorkAgentService.isConversationalPrompt('اصنع لعبة xo بالـ javascript'), isFalse);
    });
  });
}
