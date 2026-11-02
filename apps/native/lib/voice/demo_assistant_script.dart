import 'dart:convert';

import 'package:intl/intl.dart';

class DemoToolCall {
  const DemoToolCall(this.name, this.args);

  final String name;
  final Map<String, dynamic> args;
}

class DemoTurn {
  const DemoTurn({
    required this.user,
    required this.tools,
    required this.reply,
  });

  final String user;
  final List<DemoToolCall> tools;

  /// Builds the agent's reply from the results of [tools], in order.
  final String Function(List<Map<String, dynamic>> results) reply;
}

/// The conversation the demo-video build plays instead of Gemini Live. Only
/// the speech is scripted: the tool calls run for real against the account,
/// so the expense and the Home widget actually appear. It expects the account
/// prepared by `maestro/demo/prepare.sh` (the usability scenario 2 data plus
/// the "Tarjeta Mastercard" the flow creates). Dates are relative to [now] so
/// the video can be recorded on any day.
List<DemoTurn> demoAssistantScript(DateTime now) {
  final lastMonthExpenses = jsonEncode({
    'combinator': 'and',
    'children': [
      {
        'field': 'type',
        'operator': 'in',
        'value': ['expense'],
      },
      {'field': 'date', 'operator': 'relative', 'value': 'last_month'},
      {
        'field': 'currency',
        'operator': 'in',
        'value': ['ARS'],
      },
    ],
  });

  return [
    DemoTurn(
      user: 'Gasté 18.500 en el súper con la Mastercard',
      tools: const [
        DemoToolCall('addExpense', {
          'amount': 18500,
          'accountIdOrName': 'Tarjeta Mastercard',
          'categoryIdOrName': 'Supermercado',
          'name': 'Súper',
        }),
      ],
      reply: (_) =>
          'Listo, anoté 18.500 pesos en Supermercado con la Tarjeta Mastercard.',
    ),
    DemoTurn(
      user: '¿Cuánto gasté el mes pasado?',
      tools: [
        DemoToolCall('summarizeTransactions', {
          'groupBy': 'category',
          'dateFrom': _isoDay(DateTime(now.year, now.month - 1)),
          'dateTo': _isoDay(DateTime(now.year, now.month)),
          'type': 'expense',
          'currency': 'ARS',
        }),
      ],
      reply: (results) {
        final rows = [
          for (final row in results.first['rows'] as List? ?? const [])
            row as Map<String, dynamic>,
        ]..sort((a, b) => (b['total'] as num).compareTo(a['total'] as num));
        if (rows.length < 2) return 'El mes pasado casi no registraste gastos.';
        final total = rows.fold<num>(
          0,
          (sum, row) => sum + (row['total'] as num),
        );
        return 'El mes pasado gastaste ${_amount(total)} pesos. Lo que más '
            'pesó fue ${rows[0]['name']}, seguido de ${rows[1]['name']}.';
      },
    ),
    DemoTurn(
      user: '¿Y cuántos dólares tengo ahorrados?',
      tools: const [
        DemoToolCall('getAccountBalance', {'idOrName': 'Ahorro USD'}),
      ],
      reply: (results) =>
          'Tenés ${_amount(results.first['balance'] as num? ?? 0)} dólares '
          'en Ahorro USD.',
    ),
    DemoTurn(
      user:
          'Agregame en Inicio un gráfico de torta con los gastos del mes pasado',
      tools: [
        DemoToolCall('createDashboardWidget', {
          'type': 'chart',
          'title': 'Gastos del mes pasado',
          'width': 'full',
          'currency': 'ARS',
          'groupBy': 'category',
          'chartKind': 'pie',
          'filterConfigJson': lastMonthExpenses,
        }),
      ],
      reply: (_) => 'Listo, ya lo tenés en Inicio.',
    ),
  ];
}

String _isoDay(DateTime day) => DateFormat('yyyy-MM-dd').format(day);

String _amount(num value) => NumberFormat.decimalPatternDigits(
  locale: 'es',
  decimalDigits: 0,
).format(value);
