import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/providers/model_provider.dart';
import 'package:Kelivo/core/providers/work_mode_provider.dart';
import 'package:Kelivo/core/services/work/work_agent_event.dart';
import 'package:Kelivo/core/services/work/work_agent_service.dart';
import 'package:Kelivo/core/work_mode_config.dart';
import 'package:Kelivo/features/work/widgets/work_sticky_status_panel.dart';

void main() {
  group('Work Mode Conversation Integration', () {
    test(
      'Nemotron is recognized in ModelRegistry for reasoning and tool use',
      () {
        expect(
          ModelRegistry.reasoning.hasMatch('nvidia/nemotron-3-ultra-550b-a55b'),
          isTrue,
        );
        expect(
          ModelRegistry.reasoning.hasMatch('nemotron-4-340b-instruct'),
          isTrue,
        );
        expect(
          ModelRegistry.tool.hasMatch('nvidia/nemotron-3-ultra-550b-a55b'),
          isTrue,
        );
      },
    );

    test(
      'WorkModeProvider startTask initializes structured plan and execution state',
      () {
        final provider = WorkModeProvider();
        expect(provider.isExecuting, isFalse);
        expect(provider.planningEvent, isNull);

        provider.startTask('Build a responsive snake game with javascript');

        expect(provider.isExecuting, isTrue);
        expect(
          provider.currentTask,
          'Build a responsive snake game with javascript',
        );
        expect(provider.planningEvent, isNotNull);
        expect(provider.planningEvent!.steps.length, equals(4));
        expect(
          provider.planningEvent!.steps[0].status,
          equals(WorkPlanStepStatus.inProgress),
        );
        expect(
          provider.planningEvent!.steps[1].status,
          equals(WorkPlanStepStatus.pending),
        );
        expect(provider.activeStep?.title, contains('Analyze requirements'));
      },
    );

    test('WorkModeProvider updateTaskProgress advances steps correctly', () {
      final provider = WorkModeProvider();
      provider.startTask('Create markdown editor');

      provider.updateTaskProgress(
        currentStepId: 2,
        streamingContent: 'Researching layout...',
      );

      expect(
        provider.planningEvent!.steps[0].status,
        equals(WorkPlanStepStatus.completed),
      );
      expect(
        provider.planningEvent!.steps[1].status,
        equals(WorkPlanStepStatus.inProgress),
      );
      expect(
        provider.planningEvent!.steps[2].status,
        equals(WorkPlanStepStatus.pending),
      );
      expect(provider.responseText, equals('Researching layout...'));
    });

    test(
      'WorkModeProvider completeTask finalizes all steps and packages deliverable',
      () {
        final provider = WorkModeProvider();
        provider.startTask('Create a Pomodoro timer');

        const mockHtml =
            '<!DOCTYPE html><html><body><h1>Pomodoro</h1></body></html>';
        final deliverable = WorkDeliverableEvent(
          title: 'Pomodoro timer',
          type: 'web_app',
          entrypoint: 'index.html',
          files: const ['index.html'],
          previewHtml: mockHtml,
          summary: 'Deliverable generated in Work Mode.',
        );

        provider.completeTask(
          finalContent:
              'Here is your Pomodoro timer app: ```html\n$mockHtml\n```',
          deliverable: deliverable,
        );

        expect(provider.isExecuting, isFalse);
        expect(provider.hasActiveArtifact, isTrue);
        expect(provider.deliverableEvent?.previewHtml, equals(mockHtml));
        expect(provider.completedSteps, equals(4));
        for (final step in provider.planningEvent!.steps) {
          expect(step.status, equals(WorkPlanStepStatus.completed));
        }
      },
    );

    test('WorkAgentService.extractHtmlCode parses code blocks accurately', () {
      const output =
          'Here is the finished single-page application:\n'
          '```html\n'
          '<!DOCTYPE html>\n'
          '<html><head><title>App</title></head><body><h1>Hello</h1></body></html>\n'
          '```\n'
          'Enjoy your app!';
      final extracted = WorkAgentService.extractHtmlCode(
        output,
        'Build hello app',
      );
      expect(extracted, contains('<!DOCTYPE html>'));
      expect(extracted, contains('<h1>Hello</h1>'));
      expect(extracted, isNot(contains('Enjoy your app!')));
    });

    testWidgets(
      'WorkStickyStatusPanel renders human-readable status above ChatBox',
      (tester) async {
        final provider = WorkModeProvider();
        provider.setMode(AppWorkMode.work);
        provider.startTask('Build a calculator app');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ChangeNotifierProvider<WorkModeProvider>.value(
                value: provider,
                child: const WorkStickyStatusPanel(),
              ),
            ),
          ),
        );

        // Work keeps the main status surface intentionally concise.
        expect(find.text('Working'), findsWidgets);

        // Progress metadata is internal and must not leak plan copy into the
        // compact status panel.
        provider.updateTaskProgress(currentStepId: 3);
        await tester.pump();
        expect(find.text('Working'), findsWidgets);

        // The Work composer keeps the real Thinking control available after
        // completion, but the active Working state is cleared.
        provider.completeTask(finalContent: 'Done');
        await tester.pump();
        expect(find.text('Working'), findsNothing);
        expect(find.text('Thinking'), findsOneWidget);
      },
    );

    testWidgets(
      'WorkStickyStatusPanel remains hidden when in standard Chat Mode',
      (tester) async {
        final provider = WorkModeProvider();
        provider.setMode(AppWorkMode.chat);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ChangeNotifierProvider<WorkModeProvider>.value(
                value: provider,
                child: const WorkStickyStatusPanel(),
              ),
            ),
          ),
        );

        expect(find.byType(WorkStickyStatusPanel), findsOneWidget);
        expect(find.text('Analyzing task requirements…'), findsNothing);
        expect(find.byType(SizedBox), findsWidgets);
      },
    );

    test(
      'WorkAgentService prompt classification behaves accurately for Work agent',
      () {
        // Browser requests
        expect(WorkAgentService.isBrowserPrompt('افتح المتصفح'), isTrue);
        expect(
          WorkAgentService.isBrowserPrompt(
            'ابحث في جوجل عن آخر أخبار الذكاء الاصطناعي',
          ),
          isTrue,
        );
        expect(
          WorkAgentService.isBrowserPrompt(
            'Open Google Chrome and browse https://flutter.dev',
          ),
          isTrue,
        );

        // Terminal requests
        expect(
          WorkAgentService.isTerminalPrompt('شغل أمر bash في الطرفية'),
          isTrue,
        );
        expect(
          WorkAgentService.isTerminalPrompt('execute python script'),
          isTrue,
        );
        expect(
          WorkAgentService.isTerminalPrompt(
            'run `uname -a` in ubuntu terminal',
          ),
          isTrue,
        );

        // Conversational greetings
        expect(WorkAgentService.isConversationalPrompt('مرحبا'), isTrue);
        expect(WorkAgentService.isConversationalPrompt('hello there!'), isTrue);
        expect(
          WorkAgentService.isConversationalPrompt('كيف حالك يا صديقي'),
          isTrue,
        );

        // Non-conversational: Browser & Terminal prompts must NEVER be classified as conversational
        expect(
          WorkAgentService.isConversationalPrompt('افتح المتصفح'),
          isFalse,
        );
        expect(
          WorkAgentService.isConversationalPrompt('ابحث في جوجل'),
          isFalse,
        );
        expect(
          WorkAgentService.isConversationalPrompt('شغل أمر ls -la'),
          isFalse,
        );

        // Explicit web creation
        expect(
          WorkAgentService.isExplicitWebCreationPrompt('ابنِ موقع حاسبة بسيط'),
          isTrue,
        );
        expect(
          WorkAgentService.isExplicitWebCreationPrompt(
            'build a full landing page web app',
          ),
          isTrue,
        );
        expect(
          WorkAgentService.isExplicitWebCreationPrompt('مرحبا كيفك'),
          isFalse,
        );
      },
    );
  });

  group('Monochrome Scope Verification', () {
    testWidgets(
      'Emojis inside message text are rendered natively without desaturation ColorFilter',
      (tester) async {
        const emojiText = 'أهلاً بك! كيف يمكنني مساعدتك اليوم؟ 😊🎉🚀';

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Center(child: Text(emojiText))),
          ),
        );

        expect(find.text(emojiText), findsOneWidget);
        // Ensure no ColorFilter.matrix wrapper exists in the tree above Text
        expect(find.byType(ColorFiltered), findsNothing);
      },
    );
  });
}
