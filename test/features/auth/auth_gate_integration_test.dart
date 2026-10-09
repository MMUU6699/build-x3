import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Kelivo/features/auth/auth_gate.dart';
import 'package:Kelivo/features/auth/pages/auth_landing_page.dart';
import 'package:Kelivo/features/auth/providers/auth_provider.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AuthGate & AuthProvider Integration', () {
    testWidgets('Unauthenticated state renders AuthLandingPage instead of error', (
      WidgetTester tester,
    ) async {
      final authProvider = AuthProvider();
      authProvider.setStatusForTesting(AuthStatus.unauthenticated);

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: authProvider,
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: [Locale('en')],
            home: AuthGate(
              authenticatedChild: Text('Home Screen Content'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify "Authentication unavailable" is completely GONE
      expect(find.text('Authentication unavailable'), findsNothing);
      expect(
        find.textContaining('SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY'),
        findsNothing,
      );

      // Verify AuthLandingPage is shown
      expect(find.byType(AuthLandingPage), findsOneWidget);
      expect(find.text('Build X'), findsOneWidget);
      expect(find.text('Sign up'), findsOneWidget);
      expect(find.text('Log in'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
    });

    testWidgets('Authenticated state renders authenticatedChild', (
      WidgetTester tester,
    ) async {
      final authProvider = AuthProvider();
      authProvider.setStatusForTesting(AuthStatus.authenticated);

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: authProvider,
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: [Locale('en')],
            home: AuthGate(
              authenticatedChild: Text('Home Screen Content'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Authentication unavailable'), findsNothing);
      expect(find.text('Home Screen Content'), findsOneWidget);
      expect(find.byType(AuthLandingPage), findsNothing);
    });

    testWidgets('Unconfigured state renders error banner if keys are missing', (
      WidgetTester tester,
    ) async {
      final authProvider = AuthProvider();
      authProvider.setStatusForTesting(AuthStatus.unconfigured);

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: authProvider,
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: [Locale('en')],
            home: AuthGate(
              authenticatedChild: Text('Home Screen Content'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Authentication unavailable'), findsOneWidget);
    });
  });
}
