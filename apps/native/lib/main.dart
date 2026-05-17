import 'package:app/auth/auth_controller.dart';
import 'package:app/database.dart';
import 'package:app/screens/activity.dart';
import 'package:app/screens/add.dart';
import 'package:app/screens/home.dart';
import 'package:app/screens/insights.dart';
import 'package:app/screens/login.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = AuthController();
  await auth.load();
  runApp(MyApp(auth: auth));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AuthController>.value(
      value: auth,
      child: MaterialApp(
        title: 'Wallet Bot',
        theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.greenAccent)),
        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final active = context.watch<AuthController>().activeAccount;
    if (active == null) return const LoginScreen();
    return Provider<AppDatabase>(
      key: ValueKey(active.id),
      create: (_) => AppDatabase.forUser(active.id),
      dispose: (_, db) => db.close(),
      child: const AppMain(),
    );
  }
}

class AppMain extends StatefulWidget {
  const AppMain({super.key});

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
      body: IndexedStack(index: selectedIndex, children: [HomeScreen(), ActivityScreen(), Placeholder(), InsightsScreen()]),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddScreen())),
        tooltip: 'Add',
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (value) => setState(() => selectedIndex = value),
        destinations: [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: "Home"),
          NavigationDestination(icon: Icon(Icons.list_rounded), label: "Activity"),
          NavigationDestination(icon: Icon(Icons.account_balance_rounded), label: "Cuentas"),
          NavigationDestination(icon: Icon(Icons.stacked_line_chart_rounded), label: "Insights"),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}
