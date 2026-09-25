import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/features/auth/auth_gate.dart';
import 'package:Kelivo/features/auth/pages/auth_landing_page.dart';
import 'package:Kelivo/features/auth/pages/update_password_page.dart';
import 'package:Kelivo/features/auth/providers/auth_provider.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

class FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  AuthStatus _status;

  FakeAuthProvider(this._status);

  @override
  String? get configurationError => null;

  @override
  AuthStatus get status => _status;

  @override
  void setStatusForTesting(AuthStatus status) {
    _status = status;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Widget buildTestWidget(AuthProvider authProvider) {
    return ChangeNotifierProvider<AuthProvider>.value(
      value: authProvider,
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('en')],
        home: AuthGate(authenticatedChild: Text('Authenticated Content')),
      ),
    );
  }

  testWidgets('AuthGate shows loading when status is unknown', (
    WidgetTester tester,
  ) async {
    final fakeAuth = FakeAuthProvider(AuthStatus.unknown);

    await tester.pumpWidget(buildTestWidget(fakeAuth));

    expect(find.text('Build X'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Authenticated Content'), findsNothing);
  });

  testWidgets('AuthGate shows authenticatedChild when authenticated', (
    WidgetTester tester,
  ) async {
    final fakeAuth = FakeAuthProvider(AuthStatus.authenticated);

    await tester.pumpWidget(buildTestWidget(fakeAuth));

    expect(find.text('Authenticated Content'), findsOneWidget);
    expect(find.text('Build X'), findsNothing);
  });

  testWidgets('AuthGate shows AuthLandingPage when unauthenticated', (
    WidgetTester tester,
  ) async {
    final fakeAuth = FakeAuthProvider(AuthStatus.unauthenticated);

    await tester.pumpWidget(buildTestWidget(fakeAuth));

    expect(find.byType(AuthLandingPage), findsOneWidget);
    expect(find.text('Authenticated Content'), findsNothing);
  });

  testWidgets('AuthGate shows password update during recovery', (
    WidgetTester tester,
  ) async {
    final fakeAuth = FakeAuthProvider(AuthStatus.passwordRecovery);

    await tester.pumpWidget(buildTestWidget(fakeAuth));

    expect(find.byType(UpdatePasswordPage), findsOneWidget);
    expect(find.text('Authenticated Content'), findsNothing);
  });

  for (final status in const [
    AuthStatus.unconfigured,
    AuthStatus.configurationError,
  ]) {
    testWidgets('AuthGate stays closed when auth status is $status', (
      WidgetTester tester,
    ) async {
      final fakeAuth = FakeAuthProvider(status);

      await tester.pumpWidget(buildTestWidget(fakeAuth));

      expect(find.text('Authentication unavailable'), findsOneWidget);
      expect(find.text('Authenticated Content'), findsNothing);
      expect(find.byType(AuthLandingPage), findsNothing);
    });
  }
}
