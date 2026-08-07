import 'package:app/components/readable_time_picker.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uses a single-ring clock for 24-hour locales', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(useMaterial3: true),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showReadableTimePicker(
              context: context,
              initialTime: const TimeOfDay(hour: 22, minute: 0),
            ),
            child: const Text('Abrir'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(find.byType(TimePickerDialog), findsOneWidget);
    expect(find.text('Aceptar'), findsOneWidget);
    // Material 3 renders every hour on two overlapping rings. The single-ring
    // 24-hour dial labels alternating hours instead.
    expect(find.text('13'), findsNothing);
  });
}
