import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/auth/pages/auth_landing_page.dart';
import 'package:Kelivo/features/auth/pages/login_page.dart';
import 'package:Kelivo/features/auth/pages/signup_page.dart';
import 'package:Kelivo/features/auth/pages/forgot_password_page.dart';
import 'package:Kelivo/features/auth/pages/update_password_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

Widget wrapWithLocalization(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: child,
  );
}

void main() {
  testWidgets('AuthLandingPage renders branding and action buttons', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrapWithLocalization(const AuthLandingPage()));

    expect(find.text('Build X'), findsOneWidget);
    expect(find.text('Your AI workspace'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Sign up'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
  });

  testWidgets('LoginPage renders email and password fields', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrapWithLocalization(const LoginPage()));

    expect(find.text('Log in'), findsWidgets);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
  });

  testWidgets('SignupPage renders registration form fields', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrapWithLocalization(const SignupPage()));

    expect(find.text('Create account'), findsWidgets);
    expect(find.text('Display name'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
  });

  testWidgets('ForgotPasswordPage renders reset form fields', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrapWithLocalization(const ForgotPasswordPage()));

    expect(find.text('Reset password'), findsWidgets);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Send reset link'), findsOneWidget);
  });

  testWidgets('UpdatePasswordPage renders recovery form fields', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrapWithLocalization(const UpdatePasswordPage()));

    expect(find.text('Reset password'), findsWidgets);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
  });
}
