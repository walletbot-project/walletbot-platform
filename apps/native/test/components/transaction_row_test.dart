import 'package:app/components/transaction_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildRow({required bool dateConfirmed, required bool timeConfirmed}) {
    return MaterialApp(
      home: Scaffold(
        body: TransactionRow(
          title: 'Café',
          amountCents: -500,
          dateCheck: dateConfirmed,
          visualIdentities: [
            TransactionRowVisualIdentity(
              type: TransactionRowVisualIdentityType.time,
              label: '14:30',
              icon: timeConfirmed
                  ? Icons.schedule_outlined
                  : Icons.help_outline_rounded,
              color: Colors.transparent,
              attention: !timeConfirmed,
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('shows no status icon when date and time are confirmed', (
    tester,
  ) async {
    await tester.pumpWidget(buildRow(dateConfirmed: true, timeConfirmed: true));

    expect(find.byIcon(Icons.help_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.schedule_outlined), findsNothing);
  });

  testWidgets('shows one status icon for any unconfirmed combination', (
    tester,
  ) async {
    for (final state in const [
      (dateConfirmed: false, timeConfirmed: true),
      (dateConfirmed: true, timeConfirmed: false),
      (dateConfirmed: false, timeConfirmed: false),
    ]) {
      await tester.pumpWidget(
        buildRow(
          dateConfirmed: state.dateConfirmed,
          timeConfirmed: state.timeConfirmed,
        ),
      );

      expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);
    }
  });
}
