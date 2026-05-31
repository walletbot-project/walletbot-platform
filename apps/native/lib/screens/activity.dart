import 'package:flutter/material.dart';

import 'transaction_form.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  Future<void> _openTransactionForm() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const TransactionFormScreen()),
    );
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
      body: const Center(child: Text('Activity Screen')),
    );
  }
}
