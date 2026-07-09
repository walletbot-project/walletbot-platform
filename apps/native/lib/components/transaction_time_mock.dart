import 'package:flutter/material.dart';

enum TransactionTimeMockConfidence { tentativeRange, estimatedAtLoad }

class TransactionTimeMock {
  const TransactionTimeMock({required this.hour, required this.confidence});

  final int hour;
  final TransactionTimeMockConfidence confidence;

  bool get isEstimatedAtLoad =>
      confidence == TransactionTimeMockConfidence.estimatedAtLoad;

  bool get isTentativeRange =>
      confidence == TransactionTimeMockConfidence.tentativeRange;

  IconData get icon => isEstimatedAtLoad
      ? Icons.help_outline_rounded
      : timeRangeIconForHour(hour);

  String get rangeLabel {
    if (hour >= 20 || hour <= 5) return 'Noche';
    if (hour >= 6 && hour <= 12) return 'Mañana';
    return 'Tarde';
  }

  String get rangeText {
    if (hour >= 20 || hour <= 5) return '20:00-05:00';
    if (hour >= 6 && hour <= 12) return '06:00-12:00';
    return '13:00-19:00';
  }
}

TransactionTimeMock mockTransactionTime({
  required String transactionId,
  required BigInt createdAt,
}) {
  final hash = _transactionHash(transactionId);
  if (hash % 3 == 0) {
    final createdDate = DateTime.fromMillisecondsSinceEpoch(createdAt.toInt());
    return TransactionTimeMock(
      hour: createdDate.hour,
      confidence: TransactionTimeMockConfidence.estimatedAtLoad,
    );
  }

  return TransactionTimeMock(
    hour: _mockTransactionHour(transactionId),
    confidence: TransactionTimeMockConfidence.tentativeRange,
  );
}

int _mockTransactionHour(String transactionId) {
  const mockHours = [22, 9, 16];
  return mockHours[_transactionHash(transactionId) % mockHours.length];
}

int _transactionHash(String transactionId) {
  return transactionId.codeUnits.fold<int>(0, (value, unit) => value + unit);
}

IconData transactionTimeIconForHour(int hour) {
  return timeRangeIconForHour(hour);
}

IconData timeRangeIconForHour(int hour) {
  if (hour >= 20 || hour <= 5) {
    return Icons.bedtime_outlined;
  }
  if (hour >= 6 && hour <= 12) {
    return Icons.wb_twilight_outlined;
  }
  return Icons.wb_sunny_outlined;
}

String formatMockTransactionHour(int hour) {
  return '${hour.toString().padLeft(2, '0')}:00';
}
