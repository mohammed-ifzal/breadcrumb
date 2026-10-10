import 'package:flutter/material.dart';
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
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(250, 80),
                  textStyle: const TextStyle(fontSize: 24),
                ),
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
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(250, 80),
                  textStyle: const TextStyle(fontSize: 24),
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
    );
  }
}
