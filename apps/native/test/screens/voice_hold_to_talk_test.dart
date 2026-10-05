import 'dart:async';
import 'dart:convert';

import 'package:app/app_config/app_config_controller.dart';
import 'package:app/auth/account.dart';
import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/screens/voice.dart';
import 'package:app/voice/voice_event.dart';
import 'package:app/voice/voice_expense_command.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

const _capture = 'live.walletbot.app/pcm_audio/capture';
const _permission = MethodChannel('flutter.baseflow.com/permissions/methods');

class _Command extends DebugVoiceExpenseCommand {
  final controller = StreamController<VoiceEvent>.broadcast();
  final connecting = Completer<void>();
  bool connected = false;
  @override
  bool get isActive => true;
  @override
  bool get isConnected => connected;
  @override
  Stream<VoiceEvent> get events => controller.stream;
  @override
  Future<void> start({
    bool respondWithAudio = true,
    VoiceConversationMode mode = VoiceConversationMode.chat,
  }) => connecting.future;
  @override
  Future<void> addAudioChunk(Uint8List chunk) async {}
  int turnsEnded = 0;
  @override
  Future<void> endTurn() async {
    if (connected) turnsEnded += 1;
  }

  final modes = <VoiceConversationMode>[];
  @override
  Future<void> switchMode(VoiceConversationMode next) async {
    if (next == mode) return;
    mode = next;
    modes.add(next);
    connected = false;
    scheduleMicrotask(() {
      connected = true;
      controller.add(VoiceConnectedEvent());
    });
  }

  @override
  void recordClientEvent(
    String action, [
    Map<String, Object?> details = const {},
  ]) {}
  void ready() {
    connected = true;
    controller.add(VoiceConnectedEvent());
    connecting.complete();
  }
}

class _Factory extends DebugVoiceExpenseCommandFactory {
  _Factory(this.command);
  final _Command command;
  @override
  VoiceExpenseCommand create() => command;
}

const _localAccount = UserAccount(
  id: 'local-1',
  type: AccountType.local,
  name: 'Local',
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  final captureCalls = <String>[];

  setUpAll(
    () => dotenv.testLoad(
      fileInput:
          'CONVEX_URL=https://example.test\n'
          'CONVEX_SITE_URL=https://example.test',
    ),
  );
  setUp(() {
    captureCalls.clear();
    messenger.setMockMethodCallHandler(_permission, (_) async => {7: 1});
    messenger.setMockMethodCallHandler(const MethodChannel(_capture), (
      call,
    ) async {
      captureCalls.add(call.method);
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(_permission, null);
    messenger.setMockMethodCallHandler(const MethodChannel(_capture), null);
  });

  Widget app(_Command command) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: VoiceScreen(commandFactory: _Factory(command)),
  );

  // Resume carries a mic too; the composer's comes after it in the tree.
  Finder composerMic() => find.byIcon(Icons.mic_rounded).last;

  Future<void> settleCapture(WidgetTester tester) async {
    await tester.pump();
    // Stream cancellation may complete in the root zone, outside fake time.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  testWidgets('the welcome view offers to start talking', (tester) async {
    await tester.pumpWidget(app(_Command()));
    await tester.pump();

    expect(find.text('How can I help?'), findsOneWidget);
    expect(
      find.text('Tell me about an expense or ask about your accounts'),
      findsOneWidget,
    );
    expect(find.text('Talk live'), findsOneWidget);
    expect(find.text('Like a phone call (hands-free)'), findsOneWidget);
    expect(find.byTooltip('Talk live'), findsOneWidget);
    expect(find.text('Tap or hold to record a voice note'), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);

    await tester.enterText(find.byType(TextField), 'café');
    await tester.pump();
    expect(find.byTooltip('Talk live'), findsNothing);
    expect(find.text('Tap or hold to record a voice note'), findsNothing);
  });

  testWidgets(
    'holding talks and releasing closes the mic',
    (tester) async {
      await tester.pumpWidget(app(_Command()));
      await tester.pump();

      final gesture = await tester.startGesture(
        tester.getCenter(composerMic()),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await tester.pump();
      expect(captureCalls, ['listen']);
      expect(find.text('Slide up to lock'), findsOneWidget);
      expect(find.text('Tap or hold to record a voice note'), findsNothing);
      expect(find.byType(TextField), findsNothing);

      await gesture.up();
      await settleCapture(tester);
      expect(captureCalls, ['listen', 'cancel']);
      expect(find.byType(TextField), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'a press shorter than the hold delay is a tap',
    (tester) async {
      await tester.pumpWidget(app(_Command()));
      await tester.pump();

      final gesture = await tester.startGesture(
        tester.getCenter(composerMic()),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(captureCalls, isEmpty);
      await gesture.up();
      await tester.pump();
      await tester.pump();
      expect(captureCalls, ['listen']);
      expect(find.text('Pause'), findsOneWidget);
      expect(find.byTooltip('Send'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'sliding up locks the mic open until the note is sent',
    (tester) async {
      await tester.pumpWidget(app(_Command()));
      await tester.pump();

      final gesture = await tester.startGesture(
        tester.getCenter(composerMic()),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await tester.pump();
      await gesture.moveBy(const Offset(0, -100));
      await tester.pump();
      expect(find.text('Slide up to lock'), findsNothing);
      expect(find.text('Pause'), findsOneWidget);

      await gesture.up();
      await settleCapture(tester);
      expect(captureCalls, ['listen']);

      await tester.tap(find.byTooltip('Send'));
      await settleCapture(tester);
      expect(captureCalls, ['listen', 'cancel']);
      expect(find.byType(TextField), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'pausing a locked note keeps its turn open until Send',
    (tester) async {
      final command = _Command();
      await tester.pumpWidget(app(command));
      await tester.pump();
      await tester.tap(composerMic());
      await tester.pump();
      await tester.pump();
      command.ready();
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Pause'));
      await settleCapture(tester);
      expect(captureCalls, ['listen', 'cancel']);
      expect(find.text('Resume'), findsOneWidget);
      expect(command.turnsEnded, 0);

      await tester.tap(find.text('Resume'));
      await tester.pump();
      await tester.pump();
      expect(captureCalls, ['listen', 'cancel', 'listen']);
      expect(command.turnsEnded, 0);

      await tester.tap(find.byTooltip('Send'));
      await settleCapture(tester);
      expect(captureCalls, ['listen', 'cancel', 'listen', 'cancel']);
      expect(command.turnsEnded, 1);
      expect(find.byType(TextField), findsOneWidget);
      expect(command.modes, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'the composer enters live mode and X returns to the chat',
    (tester) async {
      final command = _Command();
      await tester.pumpWidget(app(command));
      await tester.pump();
      await tester.tap(composerMic());
      await tester.pump();
      await tester.pump();
      command.ready();
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await settleCapture(tester);
      expect(captureCalls, ['listen', 'cancel']);

      await tester.tap(find.byTooltip('Talk live'));
      await tester.pump();
      await tester.pump();
      expect(command.modes, [VoiceConversationMode.live]);
      expect(captureCalls, ['listen', 'cancel', 'listen']);
      expect(find.byTooltip('Exit live mode'), findsOneWidget);
      expect(find.byTooltip('Send'), findsNothing);
      expect(find.text("I'm listening"), findsOneWidget);

      await tester.tap(find.text('Pause'));
      await settleCapture(tester);
      expect(find.text('Mic paused'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);

      await tester.tap(find.byTooltip('Exit live mode'));
      await settleCapture(tester);
      expect(command.modes, [
        VoiceConversationMode.live,
        VoiceConversationMode.chat,
      ]);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byTooltip('Exit live mode'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'in live mode, pause mutes and resume reopens the mic',
    (tester) async {
      final command = _Command();
      await tester.pumpWidget(app(command));
      await tester.pump();
      await tester.tap(find.text('Talk live'));
      await tester.pump();
      await tester.pump();
      command.ready();
      await tester.pump();
      await tester.pump();
      expect(find.text("I'm listening"), findsOneWidget);

      await tester.tap(find.text('Pause'));
      await settleCapture(tester);
      expect(captureCalls, ['listen', 'cancel']);
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Mic paused'), findsOneWidget);

      await tester.tap(find.text('Resume'));
      await tester.pump();
      await tester.pump();
      expect(captureCalls, ['listen', 'cancel', 'listen']);
      expect(find.text('Pause'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'leaving live mode while the mic is still opening closes it',
    (tester) async {
      final command = _Command();
      await tester.pumpWidget(app(command));
      await tester.pump();
      await tester.tap(find.text('Talk live'));
      await tester.pump();
      await tester.pump();
      command.ready();
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Pause'));
      await settleCapture(tester);
      expect(captureCalls, ['listen', 'cancel']);

      final permission = Completer<Object?>();
      messenger.setMockMethodCallHandler(_permission, (_) => permission.future);
      await tester.tap(find.text('Resume'));
      await tester.pump();
      expect(find.text('Getting the mic ready'), findsOneWidget);

      await tester.tap(find.byTooltip('Exit live mode'));
      await settleCapture(tester);
      permission.complete({7: 1});
      await settleCapture(tester);
      expect(captureCalls.where((call) => call == 'listen'), hasLength(1));
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Pause'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'the keyboard stays up with the mic open, and typing switches to text',
    (tester) async {
      await tester.pumpWidget(app(_Command()));
      await tester.pump();
      await tester.showKeyboard(find.byType(TextField));
      FocusNode focus() => tester
          .widget<TextField>(find.byType(TextField, skipOffstage: false))
          .focusNode!;
      expect(focus().hasFocus, isTrue);

      await tester.tap(composerMic());
      await tester.pump();
      await tester.pump();
      expect(captureCalls, ['listen']);
      expect(find.text('Pause'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(focus().hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.enterText(
        find.byType(TextField, skipOffstage: false),
        'café',
      );
      await settleCapture(tester);
      expect(captureCalls, ['listen', 'cancel']);
      expect(find.text('Pause'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'café',
      );
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('suggestions fill the input when the flag is on', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repos = AppRepositories(db);
    final accountId = await repos.accounts.create(
      name: 'Efectivo',
      currency: 'ARS',
    );
    final categoryId = await repos.categories.create(name: 'Café');
    await repos.transactions.addExpense(
      accountId: accountId,
      categoryId: categoryId,
      name: 'Café',
      amountCents: BigInt.from(348700),
      currency: 'ARS',
    );
    final config = AppConfigController(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'flags': {'agentPromptSuggestions': true},
          }),
          200,
        ),
      ),
    );
    addTearDown(config.dispose);
    await config.loadAccount(_localAccount);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppRepositories>.value(value: repos),
          ChangeNotifierProvider<AppConfigController>.value(value: config),
        ],
        child: app(_Command()),
      ),
    );
    await tester.pumpAndSettle();

    final chips = find.byType(ActionChip);
    expect(chips, findsNWidgets(5));
    final label = tester
        .widget<Text>(
          find.descendant(of: chips.first, matching: find.byType(Text)),
        )
        .data!;
    await tester.tap(chips.first);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      label,
    );
  });

  testWidgets('agentRecordHint off hides the voice note hint', (tester) async {
    final config = AppConfigController(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'flags': {'agentRecordHint': false},
          }),
          200,
        ),
      ),
    );
    addTearDown(config.dispose);
    await config.loadAccount(_localAccount);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppConfigController>.value(
        value: config,
        child: app(_Command()),
      ),
    );
    await tester.pump();
    expect(find.text('Tap or hold to record a voice note'), findsNothing);
    expect(find.text('Talk live'), findsOneWidget);
  });

  for (final debug in [false, true]) {
    testWidgets(
      'tool cards show only with debugToolCalls on (debug: $debug)',
      (tester) async {
        final config = AppConfigController(
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'flags': {'debugToolCalls': debug},
              }),
              200,
            ),
          ),
        );
        addTearDown(config.dispose);
        await config.loadAccount(_localAccount);
        final command = _Command();
        await tester.pumpWidget(
          ChangeNotifierProvider<AppConfigController>.value(
            value: config,
            child: app(command),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('Talk live'));
        await tester.pump();
        await tester.pump();
        command.ready();
        command.controller.add(
          VoiceToolCallEvent(id: 't1', name: 'get_balance', args: const {}),
        );
        await tester.pump();
        await tester.pump();
        expect(find.text('get_balance'), debug ? findsOneWidget : findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
}
