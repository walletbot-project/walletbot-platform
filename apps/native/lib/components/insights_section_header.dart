import 'package:flutter/material.dart';

class InsightsSectionHeader extends StatelessWidget {
  const InsightsSectionHeader({super.key, required this.onAddPressed});

  final VoidCallback onAddPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            onPressed: onAddPressed,
            backgroundColor: Colors.greenAccent,
            foregroundColor: Colors.black,
            child: const Icon(Icons.add),
          ), // Boton de añadir (categoria o tag)
        ],
      ),
    );
  }
}
