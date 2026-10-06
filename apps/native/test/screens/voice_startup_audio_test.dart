import 'dart:async';
import 'package:app/l10n/l10n.dart';
import 'package:app/screens/voice.dart';
import 'package:app/voice/voice_event.dart';
import 'package:app/voice/voice_expense_command.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _capture = 'live.walletbot.app/pcm_audio/capture';
const _permission = MethodChannel('flutter.baseflow.com/permissions/methods');

class _Command extends DebugVoiceExpenseCommand {
  final controller = StreamController<VoiceEvent>.broadcast();
  final connecting = Completer<void>();
  final audio = <List<int>>[];
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
  }) {
    this.mode = mode;
    return connecting.future;
  }

  @override
  Future<void> addAudioChunk(Uint8List chunk) async {
    if (connected || mode == VoiceConversationMode.chat) {
      audio.add(chunk.toList());
    }
  }

  int turnsEnded = 0;
  @override
  Future<void> endTurn() async {
    turnsEnded += 1;
  }

  int discards = 0;
  @override
  void discardTurn() => discards += 1;

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

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  final captureCalls = <String>[];
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
  Future<void> open(WidgetTester tester, _Command command) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: VoiceScreen(commandFactory: _Factory(command)),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Start call'));
    await tester.pump();
    await tester.pump();
    expect(captureCalls, ['listen']);
    expect(command.connecting.isCompleted, false);
  }

  Future<void> chunk(WidgetTester tester, List<int> bytes) async {
    await messenger.handlePlatformMessage(
      _capture,
      const StandardMethodCodec().encodeSuccessEnvelope(
        Uint8List.fromList(bytes),
      ),
      (_) {},
    );
    await tester.pump();
  }

  testWidgets(
    'captures before setup and sends startup audio before live audio',
    (tester) async {
      final command = _Command();
      await open(tester, command);
      await chunk(tester, [1, 0]);
      await chunk(tester, [2, 0]);
      expect(command.audio, isEmpty);
      expect(find.text("I'm listening"), findsOneWidget);
      command.ready();
      await tester.pump();
      await chunk(tester, [3, 0]);
      expect(command.audio, [
        [1, 0],
        [2, 0],
        [3, 0],
      ]);
      command.connected = false;
      command.controller.add(VoiceDisconnectedEvent());
      await tester.pump();
      await chunk(tester, [4, 0]);
      command.connected = true;
      command.controller.add(VoiceConnectedEvent());
      await tester.pump();
      await chunk(tester, [5, 0]);
      expect(command.audio, [
        [1, 0],
        [2, 0],
        [3, 0],
        [5, 0],
      ]);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'permission pause and rapid resume-pause never strand or restart capture in background',
    (tester) async {
      final permission = Completer<Map<int, int>>();
      messenger.setMockMethodCallHandler(_permission, (_) => permission.future);
      final command = _Command();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: VoiceScreen(commandFactory: _Factory(command)),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Start call'));
      await tester.pump();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      permission.complete({7: 1});
      await tester.pump();
      await tester.pump();
      expect(captureCalls, isEmpty);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(captureCalls, ['listen']);
      command.ready();
      await tester.pump();
      await chunk(tester, [7, 0]);
      expect(command.audio, [
        [7, 0],
      ]);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'a chat note released before setup is handed to the command and ended',
    (tester) async {
      final command = _Command();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: VoiceScreen(commandFactory: _Factory(command)),
        ),
      );
      await tester.pump();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic_rounded).last),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await tester.pump();
      expect(captureCalls, ['listen']);
      await chunk(tester, [1, 0]);
      await chunk(tester, [2, 0]);
      await gesture.up();
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(captureCalls, ['listen', 'cancel']);
      expect(command.audio, [
        [1, 0],
        [2, 0],
      ]);
      expect(command.turnsEnded, 1);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  for (final cancel in [
    'tap',
    'background',
    'error',
    'overflow',
    'text',
    'leave',
  ]) {
    testWidgets(
      '$cancel discards startup audio and prevents late capture restart',
      (tester) async {
        final command = _Command();
        await open(tester, command);
        await chunk(tester, [1, 0]);
        switch (cancel) {
          case 'tap':
            await tester.tap(find.byTooltip('End call'));
          case 'background':
            binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          case 'error':
            command.controller.add(
              VoiceErrorEvent('setup failed', isTransient: true),
            );
          case 'overflow':
            await chunk(tester, List.filled(160000, 0));
          case 'text':
            // Hidden behind the recording bar, but still there for the keyboard.
            await tester.enterText(
              find.byType(TextField, skipOffstage: false),
              'hello',
            );
          case 'leave':
            await tester.pumpWidget(const SizedBox());
        }
        await tester.pump();
        // Stream cancellation may complete in the root zone, outside fake time.
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        expect(captureCalls, ['listen', 'cancel']);
        command.ready();
        await tester.pump();
        expect(command.audio, isEmpty);
        expect(captureCalls, ['listen', 'cancel']);
        await tester.pumpWidget(const SizedBox());
        if (cancel == 'background') {
          binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await tester.pump();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
}
