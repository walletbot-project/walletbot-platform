import 'package:flutter/material.dart';

int mockTransactionHour(String transactionId) {
  const mockHours = [22, 9, 16];
  final hash = transactionId.codeUnits.fold<int>(
    0,
    (value, unit) => value + unit,
  );
  return mockHours[hash % mockHours.length];
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
