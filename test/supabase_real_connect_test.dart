// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Supabase real initialization, live signup, login, session, and signout', () async {
    const url = 'https://wwiognlfiqruvcfrbler.supabase.co';
    const key = 'sb_publishable_NpI-ehjEUKbzmWD5LbE-Jg_lF6skJvH';

    final supabase = await Supabase.initialize(
      url: url,
      publishableKey: key,
    );

    expect(supabase.client, isNotNull);
    expect(supabase.client.auth, isNotNull);
    expect(supabase.client.auth.currentSession, isNull);
    print('Supabase.initialize: SUCCESS');

    // 1. Live Sign Up with email verification turned off
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final testEmail = 'buildx.user$timestamp@gmail.com';
    const testPassword = 'Password123!@#Test';
    print('Testing live sign up for: $testEmail ...');

    final signUpRes = await supabase.client.auth.signUp(
      email: testEmail,
      password: testPassword,
      data: {'display_name': 'Verified Tester'},
    );

    expect(signUpRes.user, isNotNull);
    expect(signUpRes.user!.email, equals(testEmail));
    print('Live Sign Up SUCCESS: User ID = ${signUpRes.user!.id}, Email = ${signUpRes.user!.email}');

    // With email confirmation disabled, session should be immediately active
    print('Session present immediately: ${signUpRes.session != null}');

    // 2. Sign Out
    if (supabase.client.auth.currentSession != null) {
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
    print('Live Sign In SUCCESS: User ID = ${signInRes.user!.id}, Access Token = ${signInRes.session!.accessToken.substring(0, 20)}...');

    // 4. Test authenticated session lookup
    final currentUser = supabase.client.auth.currentUser;
    expect(currentUser, isNotNull);
    expect(currentUser!.id, equals(signInRes.user!.id));
    print('Current User lookup SUCCESS: ${currentUser.email}');

    // 5. Final Sign Out
    await supabase.client.auth.signOut();
    expect(supabase.client.auth.currentSession, isNull);
    print('Final Sign Out SUCCESS');
  });
}
