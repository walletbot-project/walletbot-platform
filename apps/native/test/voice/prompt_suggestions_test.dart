// The Dart half of the prompt-suggestions parity suite. The same fixture table
// runs against the TS original in
// packages/shared/test/prompt-suggestions.test.ts. A behavioural change on one
// side fails the other side's run until both are updated together.

import 'dart:convert';
import 'dart:io';

import 'package:app/voice/prompt_suggestions.dart';
import 'package:flutter_test/flutter_test.dart';

SuggestionData _dataset(Map<String, Object?> raw) {
  List<Map<String, Object?>> list(String key) => [
    for (final item in raw[key] as List) (item as Map).cast<String, Object?>(),
  ];
  return SuggestionData(
    accounts: [
      for (final a in list('accounts'))
        SuggestionAccount(
          id: a['id'] as String,
          name: a['name'] as String,
          currency: a['currency'] as String,
        ),
    ],
    categories: [
      for (final c in list('categories'))
        SuggestionCategory(id: c['id'] as String, name: c['name'] as String),
    ],
    tags: [
      for (final t in list('tags'))
        SuggestionTag(
          name: t['name'] as String,
          usageCount: t['usageCount'] as int,
        ),
    ],
    movements: [
      for (final m in list('movements'))
        SuggestionMovement(
          type: m['type'] as String,
          amountCents: m['amountCents'] as int,
          currency: m['currency'] as String,
          accountId: m['accountId'] as String,
          categoryId: m['categoryId'] as String,
          toAccountId: m['toAccountId'] as String?,
        ),
    ],
  );
}

Map<String, Object?> _json(PromptSuggestion s) => {
  'kind': s.kind.name,
  'category': ?s.category,
  'account': ?s.account,
  'toAccount': ?s.toAccount,
  'tag': ?s.tag,
  'amountCents': ?s.amountCents,
};

PromptSuggestion _fromJson(Map<String, Object?> raw) => PromptSuggestion(
  PromptSuggestionKind.values.byName(raw['kind'] as String),
  category: raw['category'] as String?,
  account: raw['account'] as String?,
  toAccount: raw['toAccount'] as String?,
  tag: raw['tag'] as String?,
  amountCents: raw['amountCents'] as int?,
);

void main() {
  // flutter test runs with cwd = apps/native.
  final fixtures =
      jsonDecode(
            File(
              '../../packages/shared/src/prompt-suggestions-fixtures.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  final datasets = {
    for (final entry in (fixtures['datasets'] as Map).entries)
      entry.key as String: _dataset(
        (entry.value as Map).cast<String, Object?>(),
      ),
  };
  final cases = [
    for (final raw in fixtures['cases'] as List)
      (raw as Map).cast<String, Object?>(),
  ];
  List<Map<String, Object?>> expected(Map<String, Object?> c) => [
    for (final raw in c['expect'] as List) (raw as Map).cast<String, Object?>(),
  ];

  group('prompt suggestion fixtures', () {
    test('mulberry32', () {
      final raw = (fixtures['mulberry32'] as Map).cast<String, Object?>();
      final values = (raw['values'] as List).cast<double>();
      final random = mulberry32(raw['seed'] as int);
      expect([for (final _ in values) random()], values);
    });

    for (final raw in fixtures['niceAmountCents'] as List) {
      final pair = (raw as List).cast<int>();
      test('niceAmountCents(${pair[0]})', () {
        expect(niceAmountCents(pair[0]), pair[1]);
      });
    }

    for (final c in cases) {
      test(c['name'] as String, () {
        final previousCase = cases
            .where((other) => other['name'] == c['previousFrom'])
            .firstOrNull;
        final result = generatePromptSuggestions(
          datasets[c['dataset']]!,
          random: mulberry32(c['seed'] as int),
          previous: previousCase == null
              ? null
              : promptSuggestionSetKey([
                  for (final s in expected(previousCase)) _fromJson(s),
                ]),
        );
        expect([for (final s in result) _json(s)], expected(c));
      });
    }
  });
}
