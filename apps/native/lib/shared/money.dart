/// Money helpers shared by UI formatting and agent serialization.
/// Amounts are stored as int64 cents (BigInt) in the database.
library;

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

/// Signed cents for display, by transaction type: expense is negative,
/// income / incoming transfer positive, balance adjustment as stored. Matches
/// [TransactionRow]'s color convention (positive → green). Shared by the
/// activity list and the dashboard transaction-list widget so the displayed
/// sign can never diverge between them.
int signedDisplayCents(String type, BigInt amount) {
  switch (type) {
    case 'expense':
      return -amount.abs().toInt();
    case 'income':
    case 'transfer':
      return amount.abs().toInt();
    case 'balance_adjustment':
      return amount.toInt();
    default:
      return amount.toInt();
  }
}

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
