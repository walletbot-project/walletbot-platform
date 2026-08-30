// Pure helpers mirrored from packages/shared/src/tools/calc.ts and
// date-calc.ts. Keep in sync with the TS versions — both implement the same
// contract (identical accept/reject surface and results) so behavior is
// identical between web and native tool executors. Parity is locked by
// packages/shared/src/tools/calc-fixtures.json, run on this side by
// test/voice/calc_fixtures_test.dart.

import 'dart:math' as math;

import 'package:math_expressions/math_expressions.dart';

import 'tool_parsing.dart' show parseNaturalDate;

// ───── calculate ─────

/// The only callable functions. Both platforms reject anything else, even
/// where an engine knows more (mathjs knows sin; this parser knows ln).
const List<String> kCalcFunctions = [
  'abs',
  'ceil',
  'floor',
  'max',
  'min',
  'pow',
  'round',
  'sqrt',
];

const int kCalcMaxSteps = 20;
const int _maxExpressionLength = 200;

// The whole allowed alphabet. Notably absent: '=' (assignments), '%'
// (modulo semantics differ between engines), '[' and quotes (matrices,
// strings), ';' (multi-statement — steps are the multi-statement mechanism).
final RegExp _allowedChars = RegExp(r'^[0-9a-zA-Z_+\-*/^().,\s]+$');
final RegExp _identifier = RegExp(r'[a-zA-Z_][a-zA-Z0-9_]*');
final RegExp _validName = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');
// mathjs supports implicit multiplication ("2(3+1)", "2x") and scientific
// notation ("1e3"); this engine does not. The TS guard rejects all of it, so
// reject it here identically.
final List<RegExp> _implicitMultiplication = [
  RegExp(r'[0-9)]\s*\('),
  RegExp(r'\)\s*[0-9a-zA-Z_]'),
  RegExp(r'[0-9]\s*[a-zA-Z_]'),
];

/// Validates one expression against the shared syntax contract. Throws a
/// [FormatException] with a model-readable message on violation.
void validateCalcExpression(String expression, Set<String> boundNames) {
  if (expression.isEmpty) {
    throw const FormatException('Expression is empty');
  }
  if (expression.length > _maxExpressionLength) {
    throw const FormatException(
      'Expression is too long (max $_maxExpressionLength characters)',
    );
  }
  if (!_allowedChars.hasMatch(expression)) {
    throw FormatException(
      'Unsupported syntax in "$expression": only numbers, + - * / ^, '
      'parentheses, commas, step names and the functions '
      '${kCalcFunctions.join(', ')} are allowed',
    );
  }
  for (final pattern in _implicitMultiplication) {
    if (pattern.hasMatch(expression)) {
      throw FormatException(
        'Write multiplication explicitly with * in "$expression"',
      );
    }
  }
  for (final match in _identifier.allMatches(expression)) {
    final identifier = match.group(0)!;
    final rest = expression.substring(match.end);
    if (RegExp(r'^\s*\(').hasMatch(rest)) {
      if (!kCalcFunctions.contains(identifier)) {
        throw FormatException(
          'Unknown function "$identifier". Available: '
          '${kCalcFunctions.join(', ')}',
        );
      }
    } else if (!boundNames.contains(identifier)) {
      throw FormatException(
        'Unknown name "$identifier". Bind it with a previous step\'s '
        '"name" first.',
      );
    }
  }
}

double _roundFunction(List<double> args) {
  if (args.isEmpty || args.length > 2) {
    throw const FormatException('round takes 1 or 2 arguments');
  }
  if (args.length == 1) return args[0].roundToDouble();
  final digits = args[1];
  if (digits != digits.roundToDouble() || digits < 0 || digits > 15) {
    throw const FormatException(
      'round digits must be a whole number between 0 and 15',
    );
  }
  final factor = math.pow(10.0, digits).toDouble();
  return (args[0] * factor).roundToDouble() / factor;
}

double _powFunction(List<double> args) {
  if (args.length != 2) {
    throw const FormatException('pow takes 2 arguments');
  }
  return math.pow(args[0], args[1]).toDouble();
}

// abs/ceil/floor/sqrt are built into the grammar; the rest are registered as
// custom functions so the parser accepts the same set the TS side does.
final ExpressionParser _parser = () {
  final parser = GrammarParser();
  parser.addFunction('round', _roundFunction, replace: true);
  parser.addFunction('pow', _powFunction, replace: true);
  parser.addFunction('min', (args) => args.reduce(math.min), replace: true);
  parser.addFunction('max', (args) => args.reduce(math.max), replace: true);
  return parser;
}();

double _evaluateExpression(String expression, Map<String, double> scope) {
  Expression parsed;
  try {
    parsed = _parser.parse(expression);
  } catch (e) {
    throw FormatException('Could not evaluate "$expression": $e');
  }
  final context = ContextModel();
  for (final entry in scope.entries) {
    context.bindVariableName(entry.key, Number(entry.value));
  }
  double value;
  try {
    value = RealEvaluator(context).evaluate(parsed).toDouble();
  } catch (e) {
    throw FormatException('Could not evaluate "$expression": $e');
  }
  if (value.isNaN || value.isInfinite) {
    throw FormatException(
      '"$expression" did not produce a finite number '
      '(check for division by zero)',
    );
  }
  return value;
}

/// Runs the steps in order; each step may bind its result to a name for later
/// steps. Returns one `{expression, name?, value}` map per step. Throws a
/// [FormatException] on the first invalid step.
List<Map<String, Object?>> runCalculate(List<Object?> steps) {
  if (steps.isEmpty) {
    throw const FormatException('At least one step is required');
  }
  if (steps.length > kCalcMaxSteps) {
    throw const FormatException('Too many steps (max $kCalcMaxSteps)');
  }
  final scope = <String, double>{};
  final results = <Map<String, Object?>>[];
  for (final raw in steps) {
    if (raw is! Map) {
      throw const FormatException(
        'Each step must be an object with an expression',
      );
    }
    final step = raw.cast<String, Object?>();
    final rawExpression = step['expression'];
    if (rawExpression is! String) {
      throw const FormatException('Each step needs a string expression');
    }
    final expression = rawExpression.trim();
    validateCalcExpression(expression, scope.keys.toSet());
    final name = step['name'];
    if (name != null) {
      if (name is! String || !_validName.hasMatch(name)) {
        throw FormatException('Invalid step name "$name"');
      }
      if (kCalcFunctions.contains(name)) {
        throw FormatException(
          'Step name "$name" collides with a function name',
        );
      }
    }
    final value = _evaluateExpression(expression, scope);
    if (name is String) {
      scope[name] = value;
      results.add({'expression': expression, 'name': name, 'value': value});
    } else {
      results.add({'expression': expression, 'value': value});
    }
  }
  return results;
}

// ───── calculateDate ─────

const List<String> _dateUnits = ['day', 'week', 'month', 'year'];

// DateTime.weekday order: 1 = Monday.
const List<String> _weekdays = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

DateTime _parseCalendarDay(String input, DateTime now) {
  final ms = parseNaturalDate(input, now: now);
  final parsed = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
  return DateTime(parsed.year, parsed.month, parsed.day);
}

String _pad(int n, int width) => n.toString().padLeft(width, '0');

String _isoDate(DateTime d) =>
    '${_pad(d.year, 4)}-${_pad(d.month, 2)}-${_pad(d.day, 2)}';

Map<String, Object?> _dayResult(DateTime d) => {
  'date': _isoDate(d),
  'dayOfWeek': _weekdays[d.weekday - 1],
};

/// Month arithmetic clamps to the target month's last day, matching
/// date-fns addMonths on the TS side (Jan 31 + 1 month = Feb 28).
DateTime _addMonthsClamped(DateTime d, int months) {
  final zeroBased = d.year * 12 + (d.month - 1) + months;
  // Floor division (Dart ~/ truncates toward zero, wrong for negatives).
  final year = (zeroBased - (zeroBased % 12)) ~/ 12;
  final month = zeroBased - year * 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, d.day < lastDay ? d.day : lastDay);
}

DateTime _addUnits(DateTime d, int amount, String unit) {
  switch (unit) {
    case 'day':
      // Component arithmetic (not Duration) so DST transitions cannot shift
      // the calendar day — same construction as the TS mirror.
      return DateTime(d.year, d.month, d.day + amount);
    case 'week':
      return DateTime(d.year, d.month, d.day + amount * 7);
    case 'month':
      return _addMonthsClamped(d, amount);
    case 'year':
      return _addMonthsClamped(d, amount * 12);
    default:
      throw FormatException('Unknown unit: $unit');
  }
}

/// Calendar days from [from] to [to], DST-independent (UTC reconstruction).
int _daysBetween(DateTime from, DateTime to) {
  final f = DateTime.utc(from.year, from.month, from.day);
  final t = DateTime.utc(to.year, to.month, to.day);
  return t.difference(f).inDays;
}

int _wholeUnitsBetween(DateTime from, DateTime to, String unit) {
  if (unit == 'day' || unit == 'week') {
    final days = _daysBetween(from, to);
    // Dart ~/ truncates toward zero, same as the TS mirror's Math.trunc.
    return unit == 'day' ? days : days ~/ 7;
  }
  final months = (to.year - from.year) * 12 + (to.month - from.month);
  var n = unit == 'month' ? months : months ~/ 12;
  // The raw month/year count may overshoot by one because of day-of-month
  // clamping; correct toward zero until add(from, n) is not past `to`.
  if (n > 0 && _addUnits(from, n, unit).isAfter(to)) {
    n -= 1;
  } else if (n < 0 && _addUnits(from, n, unit).isBefore(to)) {
    n += 1;
  }
  return n;
}

String _requireUnit(Object? unit, String forOperation) {
  if (unit is! String || !_dateUnits.contains(unit)) {
    throw FormatException('unit is required for $forOperation');
  }
  return unit;
}

/// Executes one calculateDate operation on loosely typed tool args. Throws a
/// [FormatException] with a model-readable message on missing/invalid
/// arguments or an unparseable date.
Map<String, Object?> runCalculateDate(
  Map<String, Object?> args, {
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final operation = args['operation'];
  if (operation is! String) {
    throw const FormatException('operation is required');
  }
  final rawDate = args['date'];
  if (rawDate is! String) {
    throw const FormatException('date is required');
  }
  final base = _parseCalendarDay(rawDate, reference);
  switch (operation) {
    case 'add':
    case 'subtract':
      final amount = args['amount'];
      // Gemini may send whole numbers as doubles (3.0) — accept those,
      // reject true fractions, mirroring the TS Number.isInteger check.
      if (amount is! num || amount != amount.roundToDouble()) {
        throw const FormatException(
          'amount (a whole number of units) is required for add/subtract',
        );
      }
      final unit = _requireUnit(args['unit'], 'add/subtract');
      final signed = operation == 'add' ? amount.round() : -amount.round();
      return _dayResult(_addUnits(base, signed, unit));
    case 'diff':
      final rawOther = args['otherDate'];
      if (rawOther is! String) {
        throw const FormatException('otherDate is required for diff');
      }
      final unit = _requireUnit(args['unit'], 'diff');
      final other = _parseCalendarDay(rawOther, reference);
      return {
        'from': _isoDate(base),
        'to': _isoDate(other),
        'unit': unit,
        'value': _wholeUnitsBetween(base, other, unit),
      };
    case 'startOf':
    case 'endOf':
      final unit = args['unit'];
      if (unit is! String || !['week', 'month', 'year'].contains(unit)) {
        throw const FormatException(
          'unit (week, month or year) is required for startOf/endOf',
        );
      }
      final start = operation == 'startOf';
      switch (unit) {
        case 'week':
          // ISO weeks: Monday–Sunday, matching startOfWeek(weekStartsOn: 1).
          final monday = DateTime(
            base.year,
            base.month,
            base.day - (base.weekday - 1),
          );
          return _dayResult(
            start
                ? monday
                : DateTime(monday.year, monday.month, monday.day + 6),
          );
        case 'month':
          return _dayResult(
            start
                ? DateTime(base.year, base.month, 1)
                : DateTime(base.year, base.month + 1, 0),
          );
        default:
          return _dayResult(
            start ? DateTime(base.year, 1, 1) : DateTime(base.year, 12, 31),
          );
      }
    case 'dayOfWeek':
      return _dayResult(base);
    default:
      throw FormatException('Unknown operation: $operation');
  }
}
