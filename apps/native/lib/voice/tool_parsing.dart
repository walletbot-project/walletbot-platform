// Pure helpers mirrored from packages/shared/src/tools/parsing.ts. Keep in
// sync with the TS version — both implement the same contract so behavior is
// identical between web and native tool executors.

import 'package:app/database.dart';

export '../shared/money.dart' show parseAmountToCents;
export '../shared/text.dart' show normalizeName;

/// Parses an ISO date or a handful of natural-language English/Spanish phrases
/// to a ms-epoch BigInt. Throws on unrecognized input.
///
/// Supported phrases (case-insensitive):
///  - "today" | "hoy"
///  - "yesterday" | "ayer"
///  - "tomorrow" | "mañana" | "manana"
///  - "last Thursday" | "el jueves pasado"
///  - "3 days ago" | "hace 3 días"
BigInt parseNaturalDate(String input, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final trimmed = input.trim().toLowerCase();
  final normalized = trimmed
      .replaceAll(RegExp('[áàäâ]'), 'a')
      .replaceAll(RegExp('[éèëê]'), 'e')
      .replaceAll(RegExp('[íìïî]'), 'i')
      .replaceAll(RegExp('[óòöô]'), 'o')
      .replaceAll(RegExp('[úùüû]'), 'u');

  BigInt asDayOffset(int offset) {
    // Build the target calendar day from date components (DateTime normalizes
    // day overflow/underflow) so we land on local midnight of the right day.
    // Adding a fixed Duration(days:) would drift across a DST transition —
    // e.g. after spring-forward it lands at 23:00 the previous calendar day.
    final d = DateTime(reference.year, reference.month, reference.day + offset);
    return BigInt.from(d.millisecondsSinceEpoch);
  }

  switch (normalized) {
    case 'today':
    case 'hoy':
      return asDayOffset(0);
    case 'yesterday':
    case 'ayer':
      return asDayOffset(-1);
    case 'anteayer':
    case 'day before yesterday':
      return asDayOffset(-2);
    case 'tomorrow':
    case 'manana':
      return asDayOffset(1);
  }

  final daysAgo =
      RegExp(r'^hace\s+(\d+)\s+dias?$').firstMatch(normalized) ??
      RegExp(r'^(\d+)\s+days?\s+ago$').firstMatch(normalized);
  if (daysAgo != null) {
    return asDayOffset(-int.parse(daysAgo.group(1)!));
  }

  const weekdays = <String, int>{
    'monday': DateTime.monday,
    'lunes': DateTime.monday,
    'tuesday': DateTime.tuesday,
    'martes': DateTime.tuesday,
    'wednesday': DateTime.wednesday,
    'miercoles': DateTime.wednesday,
    'thursday': DateTime.thursday,
    'jueves': DateTime.thursday,
    'friday': DateTime.friday,
    'viernes': DateTime.friday,
    'saturday': DateTime.saturday,
    'sabado': DateTime.saturday,
    'sunday': DateTime.sunday,
    'domingo': DateTime.sunday,
  };
  final relativeWeekday =
      RegExp(r'^(?:el\s+)?([a-z]+)\s+pasado$').firstMatch(normalized) ??
      RegExp(r'^(?:el\s+)?pasado\s+([a-z]+)$').firstMatch(normalized) ??
      RegExp(r'^(?:last|this\s+past)\s+([a-z]+)$').firstMatch(normalized);
  if (relativeWeekday != null) {
    final targetWeekday = weekdays[relativeWeekday.group(1)];
    if (targetWeekday != null) {
      var daysBack = (reference.weekday - targetWeekday + 7) % 7;
      if (daysBack == 0) daysBack = 7;
      return asDayOffset(-daysBack);
    }
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

BigInt parseTransactionDate(
  String? input, {
  required TransactionTimeStatus timeStatus,
  String? time,
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final parsed = input == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          parseNaturalDate(input, now: reference).toInt(),
        );

  if (timeStatus != TransactionTimeStatus.none) {
    // A confirmed/approximate hour needs a real clock, which can arrive either
    // as the separate `time` argument or embedded in an ISO datetime `input`.
    // What we must reject is having no clock at all: otherwise we persist a
    // bare midnight flagged as a known hour, dropping the part-of-day signal
    // ("tarde", "mañana").
    if (time != null) {
      final match = RegExp(
        r'^([01]?\d|2[0-3]):([0-5]\d)$',
      ).firstMatch(time.trim());
      if (match == null) {
        throw FormatException('Invalid transaction time: $time');
      }
      final selectedDate = parsed ?? reference;
      final hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      final resolved = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        hour,
        minute,
      );
      // A time inside a DST spring-forward gap does not exist locally;
      // DateTime silently shifts it forward (e.g. 02:30 → 03:30), so the stored
      // timestamp would disagree with the supplied clock. Reject it instead of
      // persisting a wrong hour under the same timeStatus.
      if (resolved.hour != hour || resolved.minute != minute) {
        throw FormatException('Nonexistent local time: $time');
      }
      return BigInt.from(resolved.millisecondsSinceEpoch);
    }
    if (parsed == null) {
      throw ArgumentError(
        'date or time is required when timeStatus is $timeStatus',
      );
    }
    // The clock may be embedded in an ISO datetime `input`. Detect it from the
    // input string (a `HH:mm` component), not from zeroed timestamp fields — a
    // real midnight like `2026-08-06T00:00:00` is a valid confirmed time and
    // must not be mistaken for a date-only value.
    final inputHasTime =
        input != null && RegExp(r'\d{1,2}:\d{2}').hasMatch(input);
    if (!inputHasTime) {
      throw ArgumentError('time is required when timeStatus is $timeStatus');
    }
    return BigInt.from(parsed.millisecondsSinceEpoch);
  }

  if (parsed == null) return BigInt.from(reference.millisecondsSinceEpoch);
  return BigInt.from(
    DateTime(
      parsed.year,
      parsed.month,
      parsed.day,
      reference.hour,
      reference.minute,
      reference.second,
      reference.millisecond,
    ).millisecondsSinceEpoch,
  );
}
