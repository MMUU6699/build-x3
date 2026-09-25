import 'dart:io';

import '../../../support/business_test_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/backup_reminder_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tag_provider.dart';
import 'package:Kelivo/core/providers/update_provider.dart';
import 'package:Kelivo/core/providers/user_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/home/widgets/side_drawer.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/glass_pill_button.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationCachePath() async => '$path/cache';

  @override
  Future<String?> getTemporaryPath() async => '$path/tmp';
}

class _TestChatService extends ChatService {
  @override
  List<Conversation> getAllConversations() => const <Conversation>[];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _TestChatService chatService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'kelivo_side_drawer_bottom_bar_test_',
    );
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    chatService = _TestChatService();
  });

  tearDown(() async {
    await chatService.close();
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets(
    'SideDrawer bottom bar displays profile and GlassPillButton, removes gear icon',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var newConversationCalled = false;

      final userPrefs = createBusinessTestPreferences();
      final settingsPrefs = createBusinessTestPreferences();
      final assistantPrefs = createBusinessTestPreferences();
      final backupPrefs = createBusinessTestPreferences();
      final tagPrefs = createBusinessTestPreferences();

      final userProvider = UserProvider(preferences: userPrefs);
      await userProvider.setName('Alex Morgan');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ChatService>.value(value: chatService),
            ChangeNotifierProvider<SettingsProvider>(
              create: (_) => SettingsProvider(settingsPrefs),
            ),
            ChangeNotifierProvider<UserProvider>.value(value: userProvider),
            ChangeNotifierProvider<AssistantProvider>(
              create: (_) => AssistantProvider(preferences: assistantPrefs),
            ),
            ChangeNotifierProvider<BackupReminderProvider>(
              create: (_) => BackupReminderProvider(preferences: backupPrefs),
            ),
            ChangeNotifierProvider<TagProvider>(
              create: (_) => TagProvider(preferences: tagPrefs),
            ),
            ChangeNotifierProvider<UpdateProvider>(
              create: (_) => UpdateProvider(),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SideDrawer(
                userName: 'Alex Morgan',
                assistantName: 'Assistant',
                showBottomBar: true,
                embedded: true,
                onNewConversation: ({bool closeDrawer = true}) {
                  newConversationCalled = true;
                },
              ),
            ),
          ),
        ),
      );

      // SideDrawer owns repeating/long-lived animation controllers, so settling
      // is not a valid completion signal. Pump enough frames for initial layout.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify user name is present in bottom bar
      expect(find.text('Alex Morgan'), findsWidgets);

      // Verify GlassPillButton is present
      expect(find.byType(GlassPillButton), findsOneWidget);

      // Verify old settings gear icon is absent
      expect(find.byIcon(Lucide.Settings), findsNothing);

      // Tap GlassPillButton
      await tester.tap(find.byType(GlassPillButton));
      await tester.pump();

      expect(newConversationCalled, isTrue);
    },
  );
}
