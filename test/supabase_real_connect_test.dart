// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:Kelivo/core/database/chat_database_repository.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/core/services/chat/supabase_chat_sync_service.dart';
import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/core/services/work/work_agent_event.dart';
import 'package:Kelivo/core/services/work/work_agent_service.dart';
import 'package:Kelivo/core/work_mode_config.dart';

class _TestPathProvider extends PathProviderPlatform {
  _TestPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationCachePath() async => '$root/cache';

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'Supabase real initialization, auth, and chat row round-trip',
    () async {
      final url = Platform.environment['SUPABASE_URL'] ?? '';
      final key = Platform.environment['SUPABASE_KEY'] ??
          Platform.environment['SUPABASE_PUBLISHABLE_KEY'] ??
          '';

      if (url.isEmpty || key.isEmpty) {
        print('Skipping live test: SUPABASE_URL and SUPABASE_KEY not configured.');
        return;
      }

      final supabase = await Supabase.initialize(url: url, publishableKey: key);

      expect(supabase.client, isNotNull);
      expect(supabase.client.auth, isNotNull);
      expect(supabase.client.auth.currentSession, isNull);
      print('Supabase.initialize: SUCCESS');

      // 1. Live Sign Up with email verification turned off
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final testEmail =
          Platform.environment['BUILDX_TEST_EMAIL'] ??
          'buildx.user$timestamp@gmail.com';
      const testPassword = 'Password123!@#Test';
      if (Platform.environment['BUILDX_TEST_EMAIL'] == null) {
        print('Testing live sign up for: $testEmail ...');
        final signUpRes = await supabase.client.auth.signUp(
          email: testEmail,
          password: testPassword,
          data: {'display_name': 'Verified Tester'},
        );
        expect(signUpRes.user, isNotNull);
        expect(signUpRes.user!.email, equals(testEmail));
        expect(signUpRes.session, isNotNull);
        print('Live Sign Up SUCCESS: authenticated user created.');
        print('Session present immediately: ${signUpRes.session != null}');

        // 2. Sign Out
        await supabase.client.auth.signOut();
        expect(supabase.client.auth.currentSession, isNull);
        print('Sign Out SUCCESS');
      }

      // 3. Live Sign In with password
      print('Testing live sign in for: $testEmail ...');
      final signInRes = await supabase.client.auth.signInWithPassword(
        email: testEmail,
        password: testPassword,
      );

      expect(signInRes.user, isNotNull);
      expect(signInRes.user!.email, equals(testEmail));
      expect(signInRes.session, isNotNull);
      print('Live Sign In SUCCESS: authenticated session established.');

      // 4. Test authenticated session lookup
      final currentUser = supabase.client.auth.currentUser;
      expect(currentUser, isNotNull);
      expect(currentUser!.id, equals(signInRes.user!.id));
      print('Current User lookup SUCCESS: ${currentUser.email}');

      final sandboxToClean = Platform.environment['BUILDX_TEST_SANDBOX_ID'];
      if (sandboxToClean != null) {
        try {
          final cleanup = await supabase.client.functions.invoke(
            'daytona-sandbox',
            body: {'action': 'delete', 'sandbox_id': sandboxToClean},
          );
          expect(cleanup.data['action'], 'deleted');
          print('Previous integration sandbox confirmed deleted.');
        } on FunctionException catch (error) {
          expect(error.status, 404);
          print('Previous integration sandbox confirmed absent.');
        }
      }

      // Exercise the same owner-scoped rows the app's chat sync service writes.
      final conversationId = const Uuid().v4();
      final messageId = const Uuid().v4();
      final now = DateTime.now().toUtc().toIso8601String();
      await supabase.client.from('conversations').insert({
        'id': conversationId,
        'user_id': currentUser.id,
        'title': 'Supabase integration check',
        'data': {'id': conversationId, 'title': 'Supabase integration check'},
        'created_at': now,
        'updated_at': now,
      });
      await supabase.client.from('messages').insert({
        'id': messageId,
        'conversation_id': conversationId,
        'user_id': currentUser.id,
        'data': {'role': 'user', 'content': 'Build X database round-trip'},
        'created_at': now,
        'updated_at': now,
      });
      final persisted = await supabase.client
          .from('messages')
          .select('data')
          .eq('id', messageId)
          .single();
      expect(
        (persisted['data'] as Map<String, dynamic>)['content'],
        'Build X database round-trip',
      );
      print('Conversation and message RLS write/read round-trip SUCCESS.');

      // Change users before constructing the local chat service, so this test
      // checks database isolation without causing cross-account local sync.
      final otherEmail = 'buildx.other$timestamp@gmail.com';
      final otherUser = await supabase.client.auth.signUp(
        email: otherEmail,
        password: testPassword,
      );
      expect(otherUser.user, isNotNull);
      final isolatedRows = await supabase.client
          .from('messages')
          .select('id')
          .eq('id', messageId);
      expect(isolatedRows, isEmpty);
      print('Second-user RLS isolation SUCCESS.');
      await supabase.client.auth.signOut();
      await supabase.client.auth.signInWithPassword(
        email: testEmail,
        password: testPassword,
      );

      await supabase.client
          .from('conversations')
          .delete()
          .eq('id', conversationId)
          .eq('user_id', currentUser.id);
      print('Integration conversation cleanup SUCCESS.');

      // Verify the app sync layer can restore cloud rows into an independent
      // local SQLite database through the authenticated user session.
      final root = await Directory.systemTemp.createTemp('buildx-cloud-sync-');
      final previousPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TestPathProvider(root.path);
      final sourceRepository = ChatDatabaseRepository.open(
        file: File('${root.path}/source.db'),
      );
      final targetRepository = ChatDatabaseRepository.open(
        file: File('${root.path}/target.db'),
      );
      final sourceChat = ChatService(existingRepository: sourceRepository);
      final targetChat = ChatService(existingRepository: targetRepository);
      try {
        await sourceRepository.ensureReady();
        await targetRepository.ensureReady();
        await sourceChat.init();
        final cloudConversation = await sourceChat.createConversation(
          title: 'Cloud restore check',
        );
        final generated = await sourceChat.beginSendGeneration(
          conversationId: cloudConversation.id,
          userParts: const [
            TextPart('Restore this message to a second SQLite database'),
          ],
          modelId: 'z-ai/glm-5.3-flash',
          providerId: 'nvidia',
        );
        final cloudMessage = generated.userMessage!;
        await sourceChat.syncCloudChats();
        final uploadedRows = await SupabaseChatSyncService.fetchConversations();
        final uploadedMessages = await SupabaseChatSyncService.fetchMessages(
          cloudConversation.id,
        );
        expect(
          uploadedRows.any((row) => row['id'] == cloudConversation.id),
          isTrue,
        );
        final uploadedRow = uploadedRows.singleWhere(
          (row) => row['id'] == cloudConversation.id,
        );
        expect(uploadedRow['data'], isA<Map>());
        expect(
          uploadedMessages.any((row) => row['id'] == cloudMessage.id),
          isTrue,
        );

        await targetChat.init();
        await targetChat.syncCloudChats();
        final restoredConversation = await targetRepository.getConversation(
          cloudConversation.id,
        );
        final restoredMessage = await targetRepository.getMessage(
          cloudMessage.id,
        );
        expect(restoredConversation?.title, 'Cloud restore check');
        expect(
          restoredMessage?.content,
          'Restore this message to a second SQLite database',
        );
        print('App chat sync restored the cloud conversation and message.');
        await SupabaseChatSyncService.deleteConversation(cloudConversation.id);

        if (Platform.environment['RUN_DAYTONA_WORK_INTEGRATION_TESTS'] ==
            'true') {
          final prompt =
              'Create a one-page HTML field guide about safe sandbox computing. Include three practical tips.';
          final service = WorkAgentService();
          final workEvents = <WorkAgentEvent>[];
          try {
            await service
                .runTask(
                  prompt: prompt,
                  modelId: 'z-ai/glm-5.3-flash',
                  reasoningEffort: WorkReasoningEffort.medium,
                  customApiKey: '',
                )
                .timeout(const Duration(minutes: 4))
                .forEach(workEvents.add);
          } catch (error) {
            final failedRuns = await supabase.client
                .from('work_runs')
                .select('id,status,error,sandbox_id')
                .eq('user_id', currentUser.id)
                .eq('prompt', prompt)
                .order('created_at', ascending: false)
                .limit(1);
            if (failedRuns.isNotEmpty) {
              final failedRunId = failedRuns.first['id'];
              final failedEvents = await supabase.client
                  .from('work_events')
                  .select('event_type,payload')
                  .eq('run_id', failedRunId)
                  .order('sequence');
              print('Work run failed: $error');
              print('Persisted run state: $failedRuns');
              print('Persisted events: $failedEvents');
              final failedSandboxId = failedRuns.first['sandbox_id'] as String?;
              if (failedSandboxId != null) {
                try {
                  final state = await supabase.client.functions.invoke(
                    'daytona-sandbox',
                    body: {'action': 'get', 'sandbox_id': failedSandboxId},
                  );
                  print('Sandbox remained after failure: ${state.data}');
                  final cleanup = await supabase.client.functions.invoke(
                    'daytona-sandbox',
                    body: {'action': 'delete', 'sandbox_id': failedSandboxId},
                  );
                  print('Failure sandbox cleanup: ${cleanup.data}');
                } on FunctionException catch (cleanupError) {
                  if (cleanupError.status == 404) {
                    print('Failure sandbox already absent after cleanup.');
                  } else {
                    print(
                      'Failure sandbox cleanup request failed with status ${cleanupError.status}.',
                    );
                  }
                }
              }
            }
            rethrow;
          }

          expect(workEvents.whereType<WorkDoneEvent>().single.error, isNull);
          expect(workEvents.whereType<WorkBrowsingEvent>(), isNotEmpty);
          expect(
            workEvents.whereType<WorkComputerEvent>().any(
              (event) => event.screenshotBase64.isNotEmpty,
            ),
            isTrue,
          );
          expect(workEvents.whereType<WorkTerminalEvent>(), isNotEmpty);
          expect(workEvents.whereType<WorkCodingEvent>(), isNotEmpty);
          expect(workEvents.whereType<WorkDeliverableEvent>(), isNotEmpty);

          final run = await supabase.client
              .from('work_runs')
              .select('id,sandbox_id,status,result')
              .eq('user_id', currentUser.id)
              .eq('prompt', prompt)
              .order('created_at', ascending: false)
              .limit(1)
              .single();
          expect(run['status'], 'completed');
          final sandboxId = run['sandbox_id'] as String;
          final savedEvents = await supabase.client
              .from('work_events')
              .select('event_type,payload')
              .eq('run_id', run['id'])
              .order('sequence');
          final eventTypes = savedEvents
              .map((event) => event['event_type'])
              .toSet();
          expect(
            eventTypes,
            containsAll([
              'browsing',
              'computer',
              'coding',
              'terminal',
              'sandbox_deleted',
              'done',
            ]),
          );

          try {
            await supabase.client.functions.invoke(
              'daytona-sandbox',
              body: {'action': 'get', 'sandbox_id': sandboxId},
            );
            fail('Deleted sandbox was still retrievable.');
          } on FunctionException catch (error) {
            expect(error.status, 404);
          }
        }
      } finally {
        await sourceChat.close();
        await targetChat.close();
        await sourceRepository.close();
        await targetRepository.close();
        PathProviderPlatform.instance = previousPathProvider;
        await root.delete(recursive: true);
      }

      // 5. Final Sign Out
      await supabase.client.auth.signOut();
      expect(supabase.client.auth.currentSession, isNull);
      print('Final Sign Out SUCCESS');
    },
    skip: Platform.environment['RUN_SUPABASE_INTEGRATION_TESTS'] != 'true'
        ? 'Set RUN_SUPABASE_INTEGRATION_TESTS=true to create a live test user.'
        : false,
    timeout:
        Platform.environment['RUN_DAYTONA_WORK_INTEGRATION_TESTS'] == 'true'
        ? const Timeout(Duration(minutes: 6))
        : const Timeout(Duration(minutes: 2)),
  );
}
