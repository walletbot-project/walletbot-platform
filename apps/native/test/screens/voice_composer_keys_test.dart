import 'package:app/l10n/l10n.dart';
import 'package:app/screens/voice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('asks on-screen keyboards for a line break key, not send', (
    tester,
  ) async {
    await tester.pumpWidget(_voiceApp());
    await tester.showKeyboard(find.byType(TextField));

    final args = tester.testTextInput.setClientArgs!;
    expect(args['inputAction'], 'TextInputAction.newline');
    expect((args['inputType'] as Map)['name'], 'TextInputType.multiline');
  });

  testWidgets('Enter on a physical keyboard sends the message', (tester) async {
    await tester.pumpWidget(_voiceApp());

    await tester.enterText(find.byType(TextField), 'hola');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(_composerText(tester), isEmpty);
    expect(find.text('hola'), findsOneWidget);
  });

  testWidgets('Shift+Enter on a physical keyboard does not send', (
    tester,
  ) async {
    await tester.pumpWidget(_voiceApp());

    await tester.enterText(find.byType(TextField), 'hola');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(_composerText(tester), 'hola');
  });

  testWidgets('Enter that commits an input method composition does not send', (
    tester,
  ) async {
    await tester.pumpWidget(_voiceApp());

    await tester.showKeyboard(find.byType(TextField));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ni',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(_composerText(tester), 'ni');
  });
}

String _composerText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

Widget _voiceApp() => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: const VoiceScreen(),
);
