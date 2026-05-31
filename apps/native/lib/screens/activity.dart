import 'package:flutter/material.dart';

import 'transaction_form.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final List<TransactionFormResult> _transactions = [
    TransactionFormResult(
      type: TransactionFormType.income,
      accountName: 'Mercado Pago',
      accountCurrency: 'ARS',
      date: DateTime.now().subtract(const Duration(days: 1)),
      amount: 400,
      title: 'Intereses MP',
      description: null,
      categoryName: 'Intereses',
      tags: const ['rendimiento'],
    ),
    TransactionFormResult(
      type: TransactionFormType.expense,
      accountName: 'Efectivo',
      accountCurrency: 'ARS',
      date: DateTime.now().subtract(const Duration(days: 2)),
      amount: 2500,
      title: 'Almuerzo',
      description: 'Menu del dia',
      categoryName: 'Comida',
      tags: const ['oficina'],
    ),
  ];

  Future<void> _openTransactionForm() async {
    final result = await Navigator.of(context).push<TransactionFormResult>(
      MaterialPageRoute(builder: (_) => const TransactionFormScreen()),
    );

    if (result == null || !mounted) return;
    setState(() => _transactions.insert(0, result));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
        actions: [
          IconButton(
            tooltip: 'Anadir movimiento',
            onPressed: _openTransactionForm,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: _transactions.isEmpty
          ? Center(
              child: FilledButton.icon(
                onPressed: _openTransactionForm,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Anadir movimiento'),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: _transactions.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final transaction = _transactions[index];
                return _TransactionTile(transaction: transaction);
              },
            ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.transaction});

  final TransactionFormResult transaction;

  @override
  Widget build(BuildContext context) {
    final isIncome = transaction.type == TransactionFormType.income;
    final colorScheme = Theme.of(context).colorScheme;
    final amountColor = isIncome ? Colors.green.shade700 : colorScheme.error;
    final signedAmount = isIncome ? transaction.amount : -transaction.amount;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: isIncome
            ? Colors.greenAccent.shade100
            : colorScheme.errorContainer,
        child: Icon(
          isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
          color: Colors.black87,
        ),
      ),
      title: Text(
        transaction.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                transaction.accountName,
                _formatDate(transaction.date),
                if (transaction.categoryName != null) transaction.categoryName!,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (transaction.description != null ||
                transaction.tags.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (transaction.description != null)
                    Text(
                      transaction.description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  for (final tag in transaction.tags)
                    Chip(
                      label: Text(tag),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      trailing: Text(
        '${signedAmount >= 0 ? '+' : '-'}${transaction.accountCurrency} ${_formatAmount(signedAmount.abs())}',
        style: TextStyle(color: amountColor, fontWeight: FontWeight.w800),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  return '${date.day}/${date.month}/${date.year}';
}

String _formatAmount(double amount) {
  final hasCents = amount.truncateToDouble() != amount;
  return hasCents ? amount.toStringAsFixed(2) : amount.toStringAsFixed(0);
}
