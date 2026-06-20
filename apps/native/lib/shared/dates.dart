/// Epoch-millisecond helpers shared by the data layer. The database stores
/// every timestamp as int64 ms (BigInt).
library;

BigInt nowMs() => BigInt.from(DateTime.now().millisecondsSinceEpoch);

BigInt epochMs(DateTime d) => BigInt.from(d.millisecondsSinceEpoch);

DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

/// Start of the day *after* [d], for inclusive end-of-day range queries
/// (`date < endOfDayExclusiveMs(to)`).
BigInt endOfDayExclusiveMs(DateTime d) =>
    epochMs(DateTime(d.year, d.month, d.day + 1));
