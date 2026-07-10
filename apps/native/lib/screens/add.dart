import 'package:flutter/material.dart';
import 'package:app/l10n/l10n.dart';

class AddScreen extends StatefulWidget {
  const AddScreen({super.key});

  @override
  State<AddScreen> createState() => _AddScreenState();
}

class _AddScreenState extends State<AddScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.add)),
      body: Center(child: Text(context.l10n.addScreen)),
    );
  }
}
