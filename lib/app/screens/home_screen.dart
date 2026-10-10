import 'package:flutter/material.dart';
import '../theme.dart';
import '../wiring.dart';
import 'destination_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Load latest recorded map if available (D22)
    Wiring.instance.reloadActiveMap();
    // Warm Gemma AI in background
    Wiring.instance.warmAi();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Breadcrumb'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton(
                  style: BreadcrumbTheme.primaryButton,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const DestinationListScreen(),
                      ),
                    );
                  },
                  child: const Text('Navigate'),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: BreadcrumbTheme.secondaryButton.copyWith(
                    minimumSize: const WidgetStatePropertyAll(Size(220, 64)),
                    textStyle: const WidgetStatePropertyAll(
                      TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Map a route (Coming Soon)')),
                    );
                  },
                  child: const Text('Map a route'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
