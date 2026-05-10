import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  void showUserMenu() {
    showDialog(
      context: context,
      useSafeArea: false, // Ensures it covers the entire screen
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Full-screen Dialog'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.sync_rounded),
                title: const Text('Connect to account'),
                subtitle: const Text('Will backup all data'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever_rounded),
                title: const Text('Delete data'),
                subtitle: const Text('All data will be lost'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            onPressed: showUserMenu,
            icon: const Icon(Icons.person_rounded),
          ),
        ],
      ),
      body: const Center(child: Text('Home Screen')),
    );
  }
}
