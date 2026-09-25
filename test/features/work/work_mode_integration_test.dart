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

        // Must show human-readable action description
        expect(find.text('Analyzing task requirements…'), findsOneWidget);

        // Advance task step to step 3 (Generate code)
        provider.updateTaskProgress(currentStepId: 3);
        await tester.pump();
        expect(find.text('Writing code & interactive logic…'), findsOneWidget);

        // Complete task
        provider.completeTask(finalContent: 'Done');
        await tester.pump();
        expect(find.text('Task completed'), findsOneWidget);
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
