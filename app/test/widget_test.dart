// Smoke test for the widget-test harness only. The full app widget is
// not pumped here: HanimoApp boots Firebase + AppState.init (network),
// which has no place in a unit test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('test harness smoke test', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('Hanimo')));
    expect(find.text('Hanimo'), findsOneWidget);
  });
}
