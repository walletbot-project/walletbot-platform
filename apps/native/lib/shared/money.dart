/// Money helpers shared by UI formatting and agent serialization.
/// Amounts are stored as int64 cents (BigInt) in the database.
library;

import 'package:intl/intl.dart';

/// Prefix for an ISO currency: symbol for EUR/GBP, ISO code otherwise (USD, ARS).
String _currencyPrefix(String code) => switch (code) {
  'EUR' => '€',
  'GBP' => '£',
  _ => '$code ',
};

/// Formats signed cents as currency in es-AR style ('.' thousands, ',' decimals).
String formatMoney(int cents, String currency, {int decimalDigits = 2}) {
  return NumberFormat.currency(
    locale: 'es_AR',
    symbol: _currencyPrefix(currency),
    decimalDigits: decimalDigits,
  ).format(cents / 100);
}

/// Converts a decimal user-facing amount to int64 cents as BigInt.
/// `12.5` → `1250`, `-3.07` → `-307`. Throws on NaN / infinity.
BigInt parseAmountToCents(num amount) {
  final value = amount.toDouble();
  if (value.isNaN || value.isInfinite) {
    throw FormatException('Invalid amount: $amount');
  }
  final cents = (value * 100).round();
  return BigInt.from(cents);
}

/// Cents → decimal double, the wire shape the agent protocol uses.
double centsToDouble(BigInt cents) => cents.toDouble() / 100;

/// Formats absolute cents with thousands grouping: `123456` → `1,234.56`.
/// Sign and currency-symbol layout are the caller's concern (the transaction
/// row and the summary card place them differently).
String formatCentsUnsigned(int absCents) {
  final whole = absCents ~/ 100;
  final fraction = (absCents % 100).toString().padLeft(2, '0');
  final digits = whole.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return '$buffer.$fraction';
}
