import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:connect_wallet_example/main.dart';

void main() {
  testWidgets('wallet starts with review action and no automatic approval', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ConnectDemo()));
    await tester.pump();
    expect(find.text('Review request'), findsOneWidget);
    expect(find.text('Approve sign-in'), findsNothing);
  });
}
