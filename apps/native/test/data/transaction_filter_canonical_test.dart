import 'package:app/data/models/transaction_filter.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';

// fromCanonicalJson must be the inverse of toCanonicalJson for the simple-mode
// subset, so a saved filter round-trips through persistence unchanged.
void main() {
  void expectRoundTrip(TransactionFilter filter) {
    final restored = TransactionFilter.fromCanonicalJson(
      filter.toCanonicalJson(),
    );
    expect(restored.types, filter.types);
    expect(restored.status, filter.status);
    expect(restored.datePreset, filter.datePreset);
    expect(restored.accountIds, filter.accountIds);
    expect(restored.accountDirection, filter.accountDirection);
    expect(restored.categoryIds, filter.categoryIds);
    expect(restored.tagIds, filter.tagIds);
    expect(restored.tagMatch, filter.tagMatch);
    expect(restored.includeSubtags, filter.includeSubtags);
    expect(restored.currency, filter.currency);
    expect(restored.amountMinCents, filter.amountMinCents);
    expect(restored.amountMaxCents, filter.amountMaxCents);
    expect(restored.search, filter.search);
  }

  test('empty filter round-trips', () {
    expectRoundTrip(const TransactionFilter());
  });

  test('rich filter round-trips', () {
    expectRoundTrip(
      const TransactionFilter(
        types: {TxnType.expense, TxnType.income},
        status: TxnStatus.cleared,
        datePreset: DatePreset.thisMonth,
        accountIds: {'acc-1', 'acc-2'},
        accountDirection: AccountDirection.source,
        categoryIds: {'cat-1'},
        tagIds: {'tag-1'},
        tagMatch: TagMatch.all,
        includeSubtags: true,
        currency: 'ARS',
        amountMinCents: 1000,
        amountMaxCents: 50000,
        search: 'cafe',
      ),
    );
  });

  test('absolute date range round-trips to day precision', () {
    final filter = TransactionFilter(
      dateRange: DateTimeRange(
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 31),
      ),
    );
    final restored = TransactionFilter.fromCanonicalJson(
      filter.toCanonicalJson(),
    );
    expect(restored.dateRange?.start, DateTime(2026, 1, 1));
    expect(restored.dateRange?.end, DateTime(2026, 1, 31));
  });

  test('non-simple tree (or / nested group) is preserved as advanced', () {
    final restored = TransactionFilter.fromCanonicalJson({
      'combinator': 'or',
      'children': [
        {
          'field': 'type',
          'operator': 'in',
          'value': ['expense'],
        },
      ],
    });
    expect(restored.isAdvanced, isTrue);
    expect(restored.toCanonicalJson(), {
      'combinator': 'or',
      'children': [
        {
          'field': 'type',
          'operator': 'in',
          'value': ['expense'],
        },
      ],
    });
  });

  test('simple-looking advanced tree normalizes back to simple mode', () {
    final restored = TransactionFilter.advanced(
      const FilterGroup(
        children: [
          FilterCondition(field: 'type', operator: 'in', value: ['expense']),
        ],
      ),
    );
    expect(restored.isAdvanced, isFalse);
    expect(restored.types, {TxnType.expense});
  });
}
