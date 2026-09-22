import 'package:achaago_mobile/widgets/star_rating.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders five stars, filling exactly the current value', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StarRating(value: 3))),
    );

    expect(find.byIcon(Icons.star), findsNWidgets(3));
    expect(find.byIcon(Icons.star_border), findsNWidgets(2));
  });

  testWidgets('reports the tapped star back through onChanged', (tester) async {
    int? tapped;
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: StarRating(value: 0, onChanged: (value) => tapped = value))),
    );

    await tester.tap(find.byIcon(Icons.star_border).at(3));
    await tester.pump();

    expect(tapped, 4);
  });

  testWidgets('is inert when onChanged is null', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StarRating(value: 2))),
    );

    final icon = tester.widget<IconButton>(find.byType(IconButton).first);
    expect(icon.onPressed, isNull);
  });
}
