import 'package:app/screens/add_screen.dart';
import 'package:app/screens/home.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wallet Bot',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.green)),
      home: const AppMain(title: 'Wallet Bot'),
    );
  }
}

class AppMain extends StatefulWidget {
  const AppMain({super.key, required this.title});

  final String title;

  @override
  State<AppMain> createState() => _AppMainState();
}

class _AppMainState extends State<AppMain> {
  @override
  void initState() {
    super.initState();
  }

  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: selectedIndex,
        children: [HomeScreen(), Placeholder(), Placeholder(), Placeholder()],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => AddScreen())),
        tooltip: 'Add',
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
        onDestinationSelected: (value) => setState(() => selectedIndex = value),
        destinations: [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: "Home"),
          NavigationDestination(
            icon: Icon(Icons.list_rounded),
            label: "Activity",
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_rounded),
            label: "Cuentas",
          ),
          NavigationDestination(
            icon: Icon(Icons.list_rounded),
            label: "Activity",
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}
