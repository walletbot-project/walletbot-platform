/// Typed results for the summary queries. Amounts stay in BigInt cents;
/// serialization to protocol doubles happens at the tool layer.
library;

class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.name,
    required this.totalCents,
  });

  final String categoryId;
  final String name;
  final BigInt totalCents;
}

class AccountFlow {
  const AccountFlow({
    required this.accountId,
    required this.name,
    required this.currency,
    required this.inCents,
    required this.outCents,
  });

  final String accountId;
  final String name;
  final String currency;
  final BigInt inCents;
  final BigInt outCents;

  BigInt get netCents => inCents - outCents;
}
