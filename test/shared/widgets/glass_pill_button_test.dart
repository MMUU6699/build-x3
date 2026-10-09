import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/shared/widgets/glass_pill_button.dart';

void main() {
  testWidgets('GlassPillButton renders icon, label, and responds to taps', (
    WidgetTester tester,
  ) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GlassPillButton(
              icon: Lucide.Plus,
              label: 'New Chat',
              onTap: () {
                tapped = true;
              },
            ),
          ),
        ),
      ),
    );

    // Verify label is present
    expect(find.text('New Chat'), findsOneWidget);
    expect(find.byIcon(Lucide.Plus), findsOneWidget);

    // Verify semantics
    final semantics = tester.getSemantics(find.byType(GlassPillButton));
    expect(semantics.label, contains('New Chat'));

    // Tap the button
    await tester.tap(find.byType(GlassPillButton));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });
}
