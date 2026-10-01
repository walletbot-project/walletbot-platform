import 'dart:convert';

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
    await tools.execute('createAccount', {'name': 'Cash', 'currency': 'USD'});
    await tools.execute('createAccount', {'name': 'cash', 'currency': 'EUR'});

    final res = await tools.execute('getAccount', {'idOrName': 'CASH'});
    expect(res['ok'], isFalse);
    expect(res['error'], 'Account is ambiguous');
    expect(res['candidates'], hasLength(2));

    // Tools without candidate handling report plain not-found (original
    // behavior preserved).
    final bal = await tools.execute('getAccountBalance', {'idOrName': 'CASH'});
    expect(bal, {'ok': false, 'error': 'Account not found'});
  });

  test(
    'same-name accounts resolve to the one matching the default currency',
    () async {
      await tools.execute('createAccount', {'name': 'Cash', 'currency': 'ARS'});
      await tools.execute('createAccount', {'name': 'cash', 'currency': 'USD'});

      final res = await tools.execute('getAccount', {'idOrName': 'CASH'});
      expect(res['ok'], isTrue);
      expect(res['account']['currency'], 'ARS');
    },
  );

  test(
    'createAccount without a currency falls back to the default currency',
    () async {
      final res = await tools.execute('createAccount', {'name': 'Cash'});
      expect(res['ok'], isTrue);

      final acc = await tools.execute('getAccount', {'idOrName': 'Cash'});
      expect(acc['account']['currency'], 'ARS');
    },
  );

  test('deleteTransaction is idempotent', () async {
    final res = await tools.execute('deleteTransaction', {'id': 'missing'});
    // The result echoes the scope back so the model can confirm to the user
    // which of the two things it just did.
    expect(res, {'ok': true, 'id': 'missing', 'scope': 'only-this'});
  });

  group('recurring movements', () {
    Future<Map<String, dynamic>> seedSeries({String? endDate}) async {
      await tools.execute('createAccount', {'name': 'Cash', 'currency': 'ARS'});
      await tools.execute('createCategory', {'name': 'Home'});
      return await tools.execute('addExpense', {
        'accountIdOrName': 'Cash',
        'categoryIdOrName': 'Home',
        'name': 'Rent',
        'amount': 1500,
        'date': '2026-01-15',
        'dateConfirmed': true,
        'timeStatus': 'confirmed',
        'time': '09:30',
        'recurrence': {'frequency': 'monthly', 'endDate': ?endDate},
      });
    }

    test('addExpense creates the series and reports its size', () async {
      final res = await seedSeries();
      expect(res['ok'], isTrue);
      final series = res['recurrence'] as Map<String, Object?>;
      expect(series['frequency'], 'monthly');
      // The monthly batch. The model has to say this instead of "forever".
      expect(series['total'], 48);
      expect(series['coveredThrough'], isNotNull);
    });

    test('an unreadable cadence is refused, not silently dropped', () async {
      await tools.execute('createAccount', {'name': 'Cash', 'currency': 'ARS'});
      await tools.execute('createCategory', {'name': 'Home'});
      final res = await tools.execute('addExpense', {
        'accountIdOrName': 'Cash',
        'categoryIdOrName': 'Home',
        'name': 'Rent',
        'amount': 1500,
        'dateConfirmed': false,
        'timeStatus': 'none',
        'recurrence': {'frequency': 'fortnightly'},
      });
      expect(res['ok'], isFalse);
      expect(res['error'], contains('fortnightly'));
    });

    test('customDays without an interval is refused', () async {
      await tools.execute('createAccount', {'name': 'Cash', 'currency': 'ARS'});
      await tools.execute('createCategory', {'name': 'Home'});
      final res = await tools.execute('addExpense', {
        'accountIdOrName': 'Cash',
        'categoryIdOrName': 'Home',
        'name': 'Rent',
        'amount': 1500,
        'dateConfirmed': false,
        'timeStatus': 'none',
        'recurrence': {'frequency': 'customDays'},
      });
      expect(res['ok'], isFalse);
      expect(res['error'], contains('dayInterval'));
    });

    test('the occurrences stay out of listTransactions', () async {
      await seedSeries();
      final listed = await tools.execute('listTransactions', {'limit': 100});
      final items = listed['items'] as List;
      // Only what has already happened: the anchor is in the past, the rest
      // of the series is not.
      expect(items, hasLength(lessThan(48)));

      final upcoming = await tools.execute('listUpcomingTransactions', {
        'limit': 100,
      });
      expect((upcoming['items'] as List), isNotEmpty);
    });

    test('listRecurrences names the rule by its movement', () async {
      await seedSeries();
      final res = await tools.execute('listRecurrences', {});
      final items = res['items'] as List;
      expect(items, hasLength(1));
      final rule = items.single as Map<String, Object?>;
      expect(rule['name'], 'Rent');
      expect(rule['frequency'], 'monthly');
      expect(rule['amount'], 1500);
      expect(rule['id'], isNotNull);
    });

    test('getTransaction carries the series it belongs to', () async {
      final created = await seedSeries(endDate: '2026-05-31');
      final res = await tools.execute('getTransaction', {'id': created['id']});
      final txn = res['transaction'] as Map<String, Object?>;
      final series = txn['recurrence'] as Map<String, Object?>;
      expect(series['total'], 5);
      expect(series['position'], 1);
    });

    test('addRecurrenceOccurrences extends an open-ended rule', () async {
      await seedSeries();
      final rules = await tools.execute('listRecurrences', {});
      final id = (rules['items'] as List).single as Map<String, Object?>;

      final res = await tools.execute('addRecurrenceOccurrences', {
        'recurrenceId': id['id'],
      });
      expect(res['ok'], isTrue);
      expect(res['added'], 48);
    });

    test('addRecurrenceOccurrences refuses a bounded rule', () async {
      await seedSeries(endDate: '2026-05-31');
      final rules = await tools.execute('listRecurrences', {});
      final rule = (rules['items'] as List).single as Map<String, Object?>;

      final res = await tools.execute('addRecurrenceOccurrences', {
        'recurrenceId': rule['id'],
      });
      expect(res['ok'], isFalse);
      expect(res['error'], contains('end date'));
    });

    test('an all-future delete stops the rule; only-this does not', () async {
      final created = await seedSeries(endDate: '2026-05-31');

      final one = await tools.execute('deleteTransaction', {
        'id': created['id'],
        'scope': 'only-this',
      });
      expect(one['scope'], 'only-this');

      // The rest of the series is untouched, and renumbers.
      final rules = await tools.execute('listRecurrences', {});
      expect((rules['items'] as List), hasLength(1));
    });

    test('a cadence change without all-future is refused', () async {
      final created = await seedSeries();
      final res = await tools.execute('updateTransaction', {
        'id': created['id'],
        'scope': 'only-this',
        'recurrence': {'frequency': 'weekly'},
      });
      expect(res['ok'], isFalse);
      expect(res['error'], contains('all-future'));
    });

    test('an all-future date move is refused with a way forward', () async {
      final created = await seedSeries();
      final res = await tools.execute('updateTransaction', {
        'id': created['id'],
        'scope': 'all-future',
        'date': '2026-02-20',
      });
      expect(res['ok'], isFalse);
      expect(res['error'], contains('only-this'));
    });

    test('an all-future edit carries the value fields', () async {
      final created = await seedSeries(endDate: '2026-05-31');
      final res = await tools.execute('updateTransaction', {
        'id': created['id'],
        'scope': 'all-future',
        'amount': 1800,
      });
      expect(res['ok'], isTrue);
      expect(res['scope'], 'all-future');
      expect(res['changed'], 5);
    });

    test('an all-future cadence change splits the rule', () async {
      final created = await seedSeries();
      final res = await tools.execute('updateTransaction', {
        'id': created['id'],
        'scope': 'all-future',
        'recurrence': {'frequency': 'weekly'},
      });
      expect(res['ok'], isTrue);
      expect(res['splitFrom'], created['id']);
      final series = res['recurrence'] as Map<String, Object?>;
      expect(series['frequency'], 'weekly');
      expect(series['total'], 100);
    });
  });

  test('transaction tools persist and return date with timeStatus', () async {
    await tools.execute('createAccount', {'name': 'Cash', 'currency': 'ARS'});
    await tools.execute('createCategory', {'name': 'Food'});

    const exactDate = '2026-07-12T14:30:00';
    final result = await tools.execute('addExpense', {
      'accountIdOrName': 'Cash',
      'categoryIdOrName': 'Food',
      'name': 'Coffee',
      'amount': 5,
      'date': exactDate,
      'dateConfirmed': true,
      'timeStatus': 'confirmed',
    });

    expect(result['ok'], isTrue);
    expect(result['timeStatus'], 'confirmed');
    final row = (await repos.transactions.getById(result['id'] as String))!;
    expect(row.timeStatus, TransactionTimeStatus.confirmed);
    expect(
      row.date,
      BigInt.from(DateTime.parse(exactDate).millisecondsSinceEpoch),
    );
  });

  test(
    'relative day is confirmed even if the model boolean is wrong',
    () async {
      await tools.execute('createAccount', {
        'name': 'Debit',
        'currency': 'ARS',
      });
      await tools.execute('createCategory', {'name': 'Books'});

      final result = await tools.execute('addExpense', {
        'accountIdOrName': 'Debit',
        'categoryIdOrName': 'Books',
        'name': 'Libro',
        'amount': 10000,
        'date': 'el jueves pasado',
        'dateConfirmed': false,
        'timeStatus': 'none',
      });

      expect(result['ok'], isTrue);
      final row = (await repos.transactions.getById(result['id'] as String))!;
      final date = DateTime.fromMillisecondsSinceEpoch(row.date.toInt());
      expect(row.dateConfirmed, isTrue);
      expect(date.weekday, DateTime.thursday);
      expect(date.isBefore(DateTime.now()), isTrue);
    },
  );

  test('exact time without a day stays exact and defaults today', () async {
    await tools.execute('createAccount', {'name': 'Debit', 'currency': 'ARS'});
    await tools.execute('createCategory', {'name': 'Coffee'});

    final result = await tools.execute('addExpense', {
      'accountIdOrName': 'Debit',
      'categoryIdOrName': 'Coffee',
      'name': 'Café',
      'amount': 3000,
      'dateConfirmed': false,
      'timeStatus': 'confirmed',
      'time': '17:00',
    });

    expect(result['ok'], isTrue);
    final row = (await repos.transactions.getById(result['id'] as String))!;
    final date = DateTime.fromMillisecondsSinceEpoch(row.date.toInt());
    expect(row.dateConfirmed, isFalse);
    expect(row.timeStatus, TransactionTimeStatus.confirmed);
    expect((date.hour, date.minute), (17, 0));
  });

  test(
    'updateTransaction attaches/detaches tags and reports missing',
    () async {
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

      final tagged = await tools.execute('updateTransaction', {
        'id': txnId,
        'addTagIdsOrNames': ['Work', 'Nope'],
      });
      expect(tagged['ok'], isTrue);
      expect(tagged['missing'], ['Nope']);
      expect(await repos.transactions.tagIdsOf(txnId), hasLength(1));

      final untagged = await tools.execute('updateTransaction', {
        'id': txnId,
        'removeTagIdsOrNames': ['Work'],
      });
      expect(untagged['ok'], isTrue);
      expect(untagged.containsKey('missing'), isFalse);
      expect(await repos.transactions.tagIdsOf(txnId), isEmpty);
    },
  );

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
      'Cross-currency transfers require toAmount (the amount received on the destination side)',
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

    final res = await tools.execute('summarizeTransactions', {
      'groupBy': 'category',
      'dateFrom': 'yesterday',
      'dateTo': 'tomorrow',
    });
    expect(res['ok'], isTrue);
    final rows = res['rows'] as List;
    expect(rows, hasLength(1));
    expect((rows.single as Map)['total'], 12.34);
    expect((rows.single as Map)['name'], 'Food');

    final byAccount = await tools.execute('summarizeTransactions', {
      'groupBy': 'account',
      'dateFrom': 'yesterday',
      'dateTo': 'tomorrow',
    });
    expect(byAccount['ok'], isTrue);
    final accountRows = byAccount['rows'] as List;
    expect(accountRows, hasLength(1));
    expect((accountRows.single as Map)['out'], 12.34);
    expect((accountRows.single as Map)['net'], -12.34);
  });

  test(
    'dashboard widget tools preserve advanced filters and backgrounds',
    () async {
      final advancedFilter = {
        'combinator': 'and',
        'children': [
          {'field': 'date', 'operator': 'relative', 'value': 'this_month'},
          {
            'combinator': 'or',
            'children': [
              {
                'field': 'type',
                'operator': 'in',
                'value': ['expense'],
              },
              {
                'field': 'tag',
                'operator': 'in',
                'value': ['work'],
                'match': 'any',
                'includeSubtags': true,
              },
            ],
          },
        ],
      };

      final created = await tools.execute('createDashboardWidget', {
        'type': 'stat',
        'title': 'Gastos o trabajo',
        'width': 'two_thirds',
        'aggregation': 'net',
        'filterConfigJson': jsonEncode(advancedFilter),
        'background': {
          'mode': 'value',
          'low': 0,
          'high': 10000,
          'lowColor': '#FFCBCB',
          'betweenColor': '#FFE588',
          'highColor': '#C8F2D8',
        },
      });
      expect(created['ok'], isTrue);
      expect(created['filterId'], isA<String>());

      final list = await tools.execute('listDashboardWidgets', {});
      expect(list['ok'], isTrue);
      final widgets = list['widgets'] as List;
      expect(widgets, hasLength(1));
      final widget = widgets.single as Map<String, dynamic>;
      expect(widget['type'], 'stat');
      expect(widget['width'], 'two_thirds');

      final options = widget['options'] as Map;
      expect(options['title'], 'Gastos o trabajo');
      expect(options['aggregation'], 'net');
      expect((options['background'] as Map)['mode'], 'value');

      final filterConfig = widget['filterConfig'] as Map;
      expect(filterConfig['combinator'], 'and');
      expect((filterConfig['children'] as List)[1], isA<Map>());
    },
  );

  test(
    'a balance widget keeps its account scope across a partial edit',
    () async {
      final cash = await repos.accounts.create(
        name: 'Efectivo',
        currency: 'ARS',
      );

      final created = await tools.execute('createDashboardWidget', {
        'type': 'balance',
        'title': 'Solo caja',
        'currency': 'ars',
        'accountIds': [cash],
      });
      expect(created['ok'], isTrue);
      final id = created['id'] as String;

      Future<Map> optionsOf() async {
        final listed = await tools.execute('listDashboardWidgets', {});
        final widget =
            (listed['widgets'] as List).single as Map<String, dynamic>;
        return widget['options'] as Map;
      }

      expect(await optionsOf(), containsPair('currency', 'ARS'));
      expect(await optionsOf(), containsPair('accountIds', [cash]));

      // `accountIds` is a content key, so the merge drops it before writing: a
      // title-only edit must re-state it rather than silently widening the card
      // back to every account in the currency.
      final updated = await tools.execute('updateDashboardWidget', {
        'id': id,
        'title': 'Caja',
      });
      expect(updated['ok'], isTrue);

      final options = await optionsOf();
      expect(options['title'], 'Caja');
      expect(options['accountIds'], [cash]);
    },
  );

  test(
    'a balance widget scope can be cleared back to the whole currency',
    () async {
      final cash = await repos.accounts.create(
        name: 'Efectivo',
        currency: 'ARS',
      );

      final created = await tools.execute('createDashboardWidget', {
        'type': 'balance',
        'title': 'Solo caja',
        'currency': 'ARS',
        'accountIds': [cash],
      });
      final id = created['id'] as String;

      await tools.execute('updateDashboardWidget', {
        'id': id,
        'accountIds': <String>[],
      });

      final listed = await tools.execute('listDashboardWidgets', {});
      final widget = (listed['widgets'] as List).single as Map<String, dynamic>;
      expect((widget['options'] as Map)['accountIds'], isEmpty);
    },
  );

  test('dashboard widget edit updates linked filter and can archive', () async {
    final initialFilter = {
      'combinator': 'and',
      'children': [
        {
          'field': 'type',
          'operator': 'in',
          'value': ['expense'],
        },
      ],
    };
    final nextFilter = {
      'combinator': 'and',
      'children': [
        {'field': 'date', 'operator': 'relative', 'value': 'this_year'},
      ],
    };

    final created = await tools.execute('createDashboardWidget', {
      'type': 'list',
      'title': 'Últimos gastos',
      'limit': 3,
      'filterConfigJson': jsonEncode(initialFilter),
    });
    final id = created['id'] as String;
    final filterId = created['filterId'] as String;

    final updated = await tools.execute('updateDashboardWidget', {
      'id': id,
      'title': 'Movimientos del año',
      'width': 'full',
      'limit': 8,
      'filterConfigJson': jsonEncode(nextFilter),
      'background': {'mode': 'fixed', 'fixedColor': '#C7E5FF'},
    });
    expect(updated, {'ok': true, 'id': id, 'filterId': filterId});

    final savedFilter = await repos.savedFilters.getById(filterId);
    expect(savedFilter?.name, 'Movimientos del año');
    expect((jsonDecode(savedFilter!.config) as Map)['children'], hasLength(1));

    final listed = await tools.execute('listDashboardWidgets', {});
    final widget = (listed['widgets'] as List).single as Map<String, dynamic>;
    final options = widget['options'] as Map;
    expect(options['limit'], 8);
    expect((options['background'] as Map)['fixedColor'], '#C7E5FF');
    expect(
      options['layout'],
      {'row': 0, 'col': 0},
      reason: 'content edits must preserve the manual grid coordinate',
    );

    final archived = await tools.execute('archiveDashboardWidget', {'id': id});
    expect(archived, {'ok': true, 'id': id});
    final empty = await tools.execute('listDashboardWidgets', {});
    expect(empty['widgets'], isEmpty);
  });

  test('saved filter tools create update list and archive', () async {
    final config = jsonEncode({
      'combinator': 'and',
      'children': [
        {
          'field': 'currency',
          'operator': 'in',
          'value': ['ARS'],
        },
      ],
    });
    final created = await tools.execute('createSavedFilter', {
      'name': 'ARS',
      'filterConfigJson': config,
    });
    expect(created['ok'], isTrue);
    final id = created['id'] as String;

    final updated = await tools.execute('updateSavedFilter', {
      'id': id,
      'name': 'Solo ARS',
    });
    expect(updated, {'ok': true, 'id': id});

    final listed = await tools.execute('listSavedFilters', {});
    final filters = listed['filters'] as List;
    expect(filters, hasLength(1));
    expect((filters.single as Map)['name'], 'Solo ARS');

    await tools.execute('archiveSavedFilter', {'id': id});
    final empty = await tools.execute('listSavedFilters', {});
    expect(empty['filters'], isEmpty);
  });
}
