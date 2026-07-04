// Pure helpers mirrored from packages/shared/src/tools/parsing.ts. Keep in
// sync with the TS version — both implement the same contract so behavior is
// identical between web and native tool executors.

export '../shared/money.dart' show parseAmountToCents;
export '../shared/text.dart' show normalizeName;

/// Parses an ISO date or a handful of natural-language English/Spanish phrases
/// to a ms-epoch BigInt. Throws on unrecognized input.
///
/// Supported phrases (case-insensitive):
///  - "today" | "hoy"
///  - "yesterday" | "ayer"
///  - "tomorrow" | "mañana" | "manana"
BigInt parseNaturalDate(String input, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final trimmed = input.trim().toLowerCase();

  BigInt asDayOffset(int offset) {
    final d = DateTime(
      reference.year,
      reference.month,
      reference.day,
    ).add(Duration(days: offset));
    return BigInt.from(d.millisecondsSinceEpoch);
  }

  switch (trimmed) {
    case 'today':
    case 'hoy':
      return asDayOffset(0);
    case 'yesterday':
    case 'ayer':
      return asDayOffset(-1);
    case 'tomorrow':
    case 'mañana':
    case 'manana':
      return asDayOffset(1);
  }

  final parsed = DateTime.tryParse(input);
  if (parsed == null) {
    throw FormatException('Unrecognized date: $input');
  }
  return BigInt.from(parsed.millisecondsSinceEpoch);
}

BigInt? parseOptionalDate(String? input, {DateTime? now}) {
  if (input == null) return null;
  return parseNaturalDate(input, now: now);
}
