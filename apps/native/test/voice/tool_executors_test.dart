import 'package:app/data/data.dart';
import 'package:app/database.dart';
import 'package:app/voice/tool_executors.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// Locks the agent protocol envelopes ({'ok': bool, ...}, amounts as
// cents/100 doubles, idempotent deletes, ambiguity with candidates) so the
// repository refactor stays byte-compatible with what the Gemini prompt
// expects.
void main() {
  late AppDatabase db;
  late AppRepositories repos;
  late ToolExecutors tools;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repos = AppRepositories(db);
    tools = ToolExecutors(repos);
  });

  tearDown(() async {
    await db.close();
  });

  test('unknown tool', () async {
    final res = await tools.execute('nope', {});
    expect(res, {'ok': false, 'error': 'Unknown tool: nope'});
  });

  test(
    'full expense flow: create account/category, add, list, balance',
    () async {
      final acc = await tools.execute('createAccount', {
        'name': 'Cash',
        'currency': 'ARS',
      });
      expect(acc['ok'], isTrue);

      final cat = await tools.execute('createCategory', {'name': 'Food'});
      expect(cat['ok'], isTrue);

      final exp = await tools.execute('addExpense', {
        'accountIdOrName': 'cash',
        'categoryIdOrName': 'food',
        'name': 'Sandwich',
        'amount': 15.5,
        'dateConfirmed': 'true',
      });
      expect(exp['ok'], isTrue);

      final list = await tools.execute('listTransactions', {});
      expect(list['ok'], isTrue);
      final items = list['items'] as List;
      expect(items, hasLength(1));
      final item = items.single as Map<String, dynamic>;
      expect(
        item['amount'],
        15.5,
        reason: 'wire amounts are cents/100 doubles',
      );
      expect(item['type'], 'expense');

      final balance = await tools.execute('getAccountBalance', {
        'idOrName': 'Cash',
      });
      expect(balance['ok'], isTrue);
      expect(balance['balance'], -15.5);
      expect(balance['currency'], 'ARS');
    },
  );

  test('ambiguous account surfaces candidates on getAccount', () async {
    await tools.execute('createAccount', {'name': 'Cash', 'currency': 'ARS'});
    await tools.execute('createAccount', {'name': 'cash', 'currency': 'USD'});

    final res = await tools.execute('getAccount', {'idOrName': 'CASH'});
    expect(res['ok'], isFalse);
    expect(res['error'], 'Account is ambiguous');
    expect(res['candidates'], hasLength(2));

    // Tools without candidate handling report plain not-found (original
    // behavior preserved).
    final bal = await tools.execute('getAccountBalance', {'idOrName': 'CASH'});
    expect(bal, {'ok': false, 'error': 'Account not found'});
  });

  test('deleteTransaction is idempotent', () async {
    final res = await tools.execute('deleteTransaction', {'id': 'missing'});
    expect(res, {'ok': true, 'id': 'missing'});
  });

  test('tag/untag returns added/removed/missing', () async {
    await tools.execute('createAccount', {'name': 'Cash', 'currency': 'ARS'});
    await tools.execute('createCategory', {'name': 'Food'});
    await tools.execute('createTag', {'name': 'Work'});
    final exp = await tools.execute('addExpense', {
      'accountIdOrName': 'Cash',
      'categoryIdOrName': 'Food',
      'name': 'Lunch',
      'amount': 10,
    });
    final txnId = exp['id'] as String;

    final tagged = await tools.execute('tagTransaction', {
      'transactionId': txnId,
      'tagIdsOrNames': ['Work', 'Nope'],
    });
    expect(tagged['ok'], isTrue);
    expect(tagged['added'], 1);
    expect(tagged['missing'], ['Nope']);

    final untagged = await tools.execute('untagTransaction', {
      'transactionId': txnId,
      'tagIdsOrNames': ['Work'],
    });
    expect(untagged['removed'], 1);
  });

  test('transfer validation envelopes', () async {
    await tools.execute('createAccount', {'name': 'Cash', 'currency': 'ARS'});
    await tools.execute('createAccount', {'name': 'Bank', 'currency': 'USD'});

    final same = await tools.execute('addTransfer', {
      'fromAccountIdOrName': 'Cash',
      'toAccountIdOrName': 'Cash',
      'name': 'Loop',
      'amount': 10,
    });
    expect(same, {
      'ok': false,
      'error': 'Source and destination accounts must differ',
    });

    final cross = await tools.execute('addTransfer', {
      'fromAccountIdOrName': 'Cash',
      'toAccountIdOrName': 'Bank',
      'name': 'FX',
      'amount': 10,
    });
    expect(cross['ok'], isFalse);
    expect(
      cross['error'],
      'Cross-currency transfers require toAmount (or exchangeRate to derive it)',
    );
  });

  test('summaries serialize cents as doubles', () async {
    await tools.execute('createAccount', {'name': 'Cash', 'currency': 'ARS'});
    await tools.execute('createCategory', {'name': 'Food'});
    await tools.execute('addExpense', {
      'accountIdOrName': 'Cash',
      'categoryIdOrName': 'Food',
      'name': 'Lunch',
      'amount': 12.34,
      'date': 'today',
    });

    final res = await tools.execute('summarizeByCategory', {
      'dateFrom': 'yesterday',
      'dateTo': 'tomorrow',
    });
    expect(res['ok'], isTrue);
    final rows = res['rows'] as List;
    expect(rows, hasLength(1));
    expect((rows.single as Map)['total'], 12.34);
    expect((rows.single as Map)['name'], 'Food');
  });
}
