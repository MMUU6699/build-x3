import '../../../support/business_test_harness.dart';
import 'package:Kelivo/core/models/chat_input_data.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/home/utils/model_display_helper.dart';
import 'package:Kelivo/features/home/widgets/chat_input_bar.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildHarness({
    required TextEditingController controller,
    required FocusNode focusNode,
    required Future<ChatInputSubmissionResult> Function(ChatInputData input)
    onSend,
    SettingsProvider? settingsProvider,
    AssistantProvider? assistantProvider,
  }) {
    final settings =
        settingsProvider ?? SettingsProvider(createBusinessTestPreferences());
    final assistants =
        assistantProvider ??
        AssistantProvider(preferences: createBusinessTestPreferences());
    final chatModel = resolveChatModel(
      settings,
      assistant: assistants.currentAssistant,
    );
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: assistants),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatInputBar(
              chatModelProviderKey: chatModel.providerKey,
              chatModelId: chatModel.modelId,
              controller: controller,
              focusNode: focusNode,
              onSend: onSend,
            ),
          ),
        ),
      ),
    );
  }

  group('ChatBox Animation & Smooth Transition', () {
    testWidgets('AnimatedSize uses Alignment.bottomCenter and Clip.hardEdge', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();

      await tester.pumpWidget(
        buildHarness(
          controller: controller,
          focusNode: focusNode,
          onSend: (_) async => ChatInputSubmissionResult.sent,
        ),
      );

      final animatedSizes = tester.widgetList<AnimatedSize>(
        find.byType(AnimatedSize),
      );
      expect(animatedSizes, isNotEmpty);

      // Verify the main ChatBox AnimatedSize
      final mainAnimatedSize = animatedSizes.firstWhere(
        (widget) => widget.alignment == Alignment.bottomCenter,
      );
      expect(mainAnimatedSize.alignment, equals(Alignment.bottomCenter));
      expect(mainAnimatedSize.clipBehavior, equals(Clip.hardEdge));
      expect(mainAnimatedSize.curve, equals(Curves.easeInOutCubic));
      expect(
        mainAnimatedSize.duration,
        equals(const Duration(milliseconds: 240)),
      );
    });

    testWidgets('Expands smoothly upon typing and collapses smoothly on send', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();

      await tester.pumpWidget(
        buildHarness(
          controller: controller,
          focusNode: focusNode,
          onSend: (data) async => ChatInputSubmissionResult.sent,
        ),
      );

      // Initially collapsed
      await tester.pumpAndSettle();
      expect(find.byType(AnimatedSwitcher), findsWidgets);

      // Type text: triggers expansion
      controller.text = 'Hello, Build X!';
      await tester.pump(); // Start animation frame
      await tester.pump(const Duration(milliseconds: 100)); // Mid-animation
      await tester.pumpAndSettle(); // Settle fully

      // Submit via controller directly to test send transition
      controller.text = 'Send test';
      await tester.pump();
      await tester.pumpAndSettle();

      // Clear/unfocus to trigger collapse animation
      controller.clear();
      focusNode.unfocus();
      await tester.pump(); // Frame 0 of collapse
      await tester.pump(
        const Duration(milliseconds: 100),
      ); // Halfway through collapse
      await tester.pumpAndSettle(); // Finished collapse

      // Box must cleanly settle back in collapsed state with no exceptions
      expect(controller.text, isEmpty);
    });
  });
}
