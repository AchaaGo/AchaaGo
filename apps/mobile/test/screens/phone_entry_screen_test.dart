import 'package:achaago_mobile/screens/login/phone_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Only exercises client-side validation (digit counting / formatting):
/// tapping "continue" for real would reach [AppScope], which needs a
/// network-backed [AppState]. That request/response path is covered by
/// the ApiClient tests instead.
void main() {
  testWidgets('continue button stays disabled until exactly 8 digits are entered', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PhoneEntryScreen()));

    ElevatedButton continueButton() => tester.widget<ElevatedButton>(find.byType(ElevatedButton));

    expect(continueButton().onPressed, isNull);

    await tester.enterText(find.byType(TextField), '9911223');
    await tester.pump();
    expect(continueButton().onPressed, isNull);

    await tester.enterText(find.byType(TextField), '99112233');
    await tester.pump();
    expect(continueButton().onPressed, isNotNull);
  });

  testWidgets('formats the phone number into two groups of four as it is typed', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PhoneEntryScreen()));

    await tester.enterText(find.byType(TextField), '99112233');
    await tester.pump();

    expect(find.text('9911 2233'), findsOneWidget);
  });

  testWidgets('ignores non-digit characters and caps input at 8 digits', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PhoneEntryScreen()));

    await tester.enterText(find.byType(TextField), '99-11 22 33 44 55');
    await tester.pump();

    expect(find.text('9911 2233'), findsOneWidget);
  });
}
