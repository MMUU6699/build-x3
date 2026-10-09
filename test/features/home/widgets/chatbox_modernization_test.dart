import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/database/extension_entity_store.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/instruction_injection_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/work_mode_provider.dart';
import 'package:Kelivo/core/providers/world_book_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/core/services/skills/skills_service.dart';
import 'package:Kelivo/features/home/widgets/chat_input_bar.dart';
import 'package:Kelivo/features/home/widgets/mode_segmented_toggle.dart';
import 'package:Kelivo/features/chat/widgets/bottom_tools_sheet.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import '../../../support/business_test_harness.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildHarness({
    required Widget child,
    SettingsProvider? settingsProvider,
    AssistantProvider? assistantProvider,
    WorkModeProvider? workModeProvider,
    WorldBookProvider? worldBookProvider,
    InstructionInjectionProvider? instructionInjectionProvider,
    SkillsService? skillsService,
    ChatService? chatService,
  }) {
    final settings =
        settingsProvider ?? SettingsProvider(createBusinessTestPreferences());
    final assistants =
        assistantProvider ??
        AssistantProvider(preferences: createBusinessTestPreferences());
    final workMode = workModeProvider ?? WorkModeProvider();
    final worldBook =
        worldBookProvider ??
        WorldBookProvider(preferences: createBusinessTestPreferences());
    final injection =
        instructionInjectionProvider ??
        InstructionInjectionProvider(
          preferences: createBusinessTestPreferences(),
        );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: assistants),
        ChangeNotifierProvider.value(value: workMode),
        ChangeNotifierProvider.value(value: worldBook),
        ChangeNotifierProvider.value(value: injection),
        if (skillsService != null)
          ChangeNotifierProvider.value(value: skillsService),
        if (chatService != null)
          ChangeNotifierProvider.value(value: chatService),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
  }

  group('ChatBox Modernization & Focus Tests', () {
    testWidgets(
      'Focus persists on ChatBox when app lifecycle transitions occur (no premature unfocus)',
      (tester) async {
        final controller = TextEditingController();
        final focusNode = FocusNode();

        await tester.pumpWidget(
          buildHarness(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ChatInputBar(controller: controller, focusNode: focusNode),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Initially no focus
        expect(focusNode.hasFocus, isFalse);

        // Repeat from an unfocused state to catch focus being lost during the
        // composer expand/rebuild animation after the initial tap.
        for (var attempt = 0; attempt < 10; attempt++) {
          if (focusNode.hasFocus) {
            focusNode.unfocus();
            await tester.pumpAndSettle();
          }
          await tester.tap(find.byType(TextField));
          await tester.pumpAndSettle();
          expect(
            focusNode.hasFocus,
            isTrue,
            reason: 'ChatBox must keep focus after tap ${attempt + 1}',
          );
        }

        // Simulate Android lifecycle events: inactive (e.g. keyboard popping up) and resumed
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        expect(
          focusNode.hasFocus,
          isTrue,
          reason: 'Focus must not be dropped when app transitions to inactive',
        );

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        // Advance time to allow the 300ms context menu timer in didChangeAppLifecycleState to complete cleanly
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          focusNode.hasFocus,
          isTrue,
          reason: 'Focus must not be dropped when app transitions to resumed',
        );
      },
    );

    testWidgets(
      'Dynamic text direction detection: RTL for Arabic, LTR for English',
      (tester) async {
        final controller = TextEditingController();
        final focusNode = FocusNode();

        await tester.pumpWidget(
          buildHarness(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ChatInputBar(controller: controller, focusNode: focusNode),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. English input -> LTR
        controller.text = 'Hello world';
        await tester.pumpAndSettle();
        var textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.textDirection, equals(TextDirection.ltr));

        // 2. Arabic input -> RTL
        controller.text = 'مرحبا بك';
        await tester.pumpAndSettle();
        textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.textDirection, equals(TextDirection.rtl));

        // 3. Mixed starting with Arabic -> RTL
        controller.text = 'مرحبا Hello';
        await tester.pumpAndSettle();
        textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.textDirection, equals(TextDirection.rtl));

        // 4. Mixed starting with English -> LTR
        controller.text = 'Hello مرحبا';
        await tester.pumpAndSettle();
        textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.textDirection, equals(TextDirection.ltr));
      },
    );

    testWidgets(
      'ModeSegmentedToggle is suspended and renders empty widget (Work mode removed from UI)',
      (tester) async {
        final workModeProvider = WorkModeProvider();

        await tester.pumpWidget(
          buildHarness(
            workModeProvider: workModeProvider,
            child: const Center(child: ModeSegmentedToggle()),
          ),
        );
        await tester.pumpAndSettle();

        // Work mode switcher is completely removed from the UI
        expect(find.text('Work'), findsNothing);
        expect(workModeProvider.isWorkMode, isFalse);
      },
    );

    testWidgets(
      'BottomToolsSheet exposes consumer-friendly tools without developer jargon',
      (tester) async {
        final business = await createBusinessTestHarness();
        final skillsService = SkillsService(
          store: ExtensionEntityStore(business.database),
        );
        final chatService = ChatService();
        addTearDown(chatService.close);

        await tester.pumpWidget(
          buildHarness(
            skillsService: skillsService,
            chatService: chatService,
            child: const BottomToolsSheet(webSearchActive: true),
          ),
        );
        await tester.pumpAndSettle();

        // Consumer friendly title and labels
        expect(find.text('Tools & Capabilities'), findsOneWidget);
        expect(find.text('Search the Web'), findsOneWidget);
        expect(
          find.text('Find real-time answers and sources online'),
          findsOneWidget,
        );

        // Jargon absence check
        expect(find.textContaining('API Key'), findsNothing);
        expect(find.textContaining('curl'), findsNothing);
        expect(find.textContaining('Endpoint'), findsNothing);
        expect(find.textContaining('JSON Schema'), findsNothing);
      },
    );
  });
}
