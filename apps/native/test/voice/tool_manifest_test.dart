// Golden parity test for the native executor set (the web side is
// compile-enforced via `satisfies Record<ToolName, ToolExecutor>`; the Dart
// switch has no such check, so this locks it to the generated manifest).

import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/voice/agent_generated.dart';
import 'package:app/voice/tool_executors.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ToolExecutors tools;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tools = ToolExecutors(AppRepositories(db));
  });

  tearDown(() async {
    await db.close();
  });

  test('every shared tool name has a native executor', () async {
    for (final name in kAgentToolNames) {
      // Empty args may fail validation inside the executor — that is fine;
      // what must never happen is the switch not knowing the tool at all.
      final result = await tools.execute(name, {});
      expect(
        result['error'],
        isNot('Unknown tool: $name'),
        reason: '$name is declared to the model but has no native executor',
      );
    }
  });

  test('an undeclared tool is rejected', () async {
    final result = await tools.execute('definitelyNotATool', {});
    expect(result, {'ok': false, 'error': 'Unknown tool: definitelyNotATool'});
  });
}
