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
