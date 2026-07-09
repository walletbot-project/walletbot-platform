import 'package:flutter/material.dart';

enum TransactionTimeMockConfidence { known, approximate, estimatedAtLoad }

enum TransactionTimeApproximation { morning, noon, afternoon, night }

class TransactionTimeMock {
  const TransactionTimeMock({
    required this.hour,
    required this.confidence,
    this.approximation,
  });

  final int hour;
  final TransactionTimeMockConfidence confidence;
  final TransactionTimeApproximation? approximation;

  bool get isKnown => confidence == TransactionTimeMockConfidence.known;

  bool get isApproximate =>
      confidence == TransactionTimeMockConfidence.approximate;

  bool get isEstimatedAtLoad =>
      confidence == TransactionTimeMockConfidence.estimatedAtLoad;

  bool get needsAttention => isApproximate || isEstimatedAtLoad;

  IconData get icon =>
      needsAttention ? Icons.help_outline_rounded : Icons.schedule_outlined;

  String get rowText => formatMockTransactionHour(hour);

  String get approximationLabel {
    return switch (approximation) {
      TransactionTimeApproximation.morning => 'Mañana',
      TransactionTimeApproximation.noon => 'Mediodía',
      TransactionTimeApproximation.afternoon => 'Tarde',
      TransactionTimeApproximation.night => 'Noche',
      null => rangeLabel,
    };
  }

  String get rangeLabel {
    if (hour >= 20 || hour <= 5) return 'Noche';
    if (hour >= 6 && hour <= 12) return 'Mañana';
    if (hour == 13) return 'Mediodía';
    return 'Tarde';
  }

  String get detailLabel {
    if (isKnown) return 'Horario';
    if (isApproximate) return 'Horario aproximado';
    return 'Horario estimado';
  }

  String get detailText {
    if (isKnown) return rowText;
    if (isApproximate) {
      return '$rowText · aproximado: $approximationLabel';
    }
    return '$rowText · asumido al momento de carga';
  }
}

TransactionTimeMock mockTransactionTime({
  required String transactionId,
  required BigInt createdAt,
}) {
  final hash = _transactionHash(transactionId);
  switch (hash % 6) {
    case 0:
      final createdDate = DateTime.fromMillisecondsSinceEpoch(
        createdAt.toInt(),
      );
      return TransactionTimeMock(
        hour: createdDate.hour,
        confidence: TransactionTimeMockConfidence.estimatedAtLoad,
      );
    case 1:
      return TransactionTimeMock(
        hour: 8 + (hash % 12),
        confidence: TransactionTimeMockConfidence.known,
      );
    case 2:
      return const TransactionTimeMock(
        hour: 10,
        confidence: TransactionTimeMockConfidence.approximate,
        approximation: TransactionTimeApproximation.morning,
      );
    case 3:
      return const TransactionTimeMock(
        hour: 13,
        confidence: TransactionTimeMockConfidence.approximate,
        approximation: TransactionTimeApproximation.noon,
      );
    case 4:
      return const TransactionTimeMock(
        hour: 16,
        confidence: TransactionTimeMockConfidence.approximate,
        approximation: TransactionTimeApproximation.afternoon,
      );
    default:
      return const TransactionTimeMock(
        hour: 22,
        confidence: TransactionTimeMockConfidence.approximate,
        approximation: TransactionTimeApproximation.night,
      );
  }
}

int _transactionHash(String transactionId) {
  return transactionId.codeUnits.fold<int>(0, (value, unit) => value + unit);
}

IconData transactionTimeIconForHour(int hour) {
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
