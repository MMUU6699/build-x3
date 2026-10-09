import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/home/widgets/chat_input_bar.dart';
import 'package:Kelivo/icons/reasoning_icons.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import '../../../support/business_test_harness.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('ReasoningIcons.labelForBudget maps correctly', () {
    expect(ReasoningIcons.labelForBudget(null), equals('Auto'));
    expect(ReasoningIcons.labelForBudget(-1), equals('Auto'));
    expect(ReasoningIcons.labelForBudget(0), equals('Off'));
    expect(ReasoningIcons.labelForBudget(1024), equals('Low'));
    expect(ReasoningIcons.labelForBudget(16000), equals('Medium'));
    expect(ReasoningIcons.labelForBudget(32000), equals('High'));
    expect(ReasoningIcons.labelForBudget(64000), equals('64k'));
    expect(ReasoningIcons.labelForBudget(128000), equals('128k'));
  });

  testWidgets('ChatInputBar displays reasoning chip with active level label', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    var configured = false;

    final settings = SettingsProvider(createBusinessTestPreferences());
    final assistants = AssistantProvider(
      preferences: createBusinessTestPreferences(),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: assistants),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ChatInputBar(
              controller: controller,
              focusNode: focusNode,
              supportsReasoning: true,
              reasoningActive: true,
              reasoningBudget: 64000,
              onConfigureReasoning: () {
                configured = true;
              },
            ),
          ),
        ),
      ),
    );

    // Expand to show actions row
    controller.text = 'testing';
    await tester.pumpAndSettle();

    // Verify chip text '64k' is rendered
    expect(find.text('64k'), findsOneWidget);

    // Tap chip
    await tester.tap(find.text('64k'));
    await tester.pumpAndSettle();

    expect(configured, isTrue);
  });
}
