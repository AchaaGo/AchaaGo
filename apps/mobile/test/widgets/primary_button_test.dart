import 'package:achaago_mobile/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows its label and calls onPressed when tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PrimaryButton(label: 'Үргэлжлүүлэх', onPressed: () => tapped = true)),
      ),
    );

    expect(find.text('Үргэлжлүүлэх'), findsOneWidget);
    await tester.tap(find.byType(ElevatedButton));
    expect(tapped, isTrue);
  });

  testWidgets('is disabled when onPressed is null', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PrimaryButton(label: 'Баталгаажуулах', onPressed: null))),
    );

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('shows a spinner instead of the label while busy, and disables the button', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PrimaryButton(label: 'Баталгаажуулах', busy: true, onPressed: () => tapped = true)),
      ),
    );

    expect(find.text('Баталгаажуулах'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
    expect(tapped, isFalse);
  });
}
