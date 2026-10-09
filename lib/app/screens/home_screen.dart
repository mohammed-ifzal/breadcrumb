import 'package:flutter/material.dart';
import 'destination_list_screen.dart';
import 'replay_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Breadcrumb')),
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
                    MaterialPageRoute(builder: (context) => const DestinationListScreen()),
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
              const SizedBox(height: 24),
              OutlinedButton.icon(
                icon: const Icon(Icons.replay, size: 28),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(250, 60),
                  textStyle: const TextStyle(fontSize: 20),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ReplayScreen()),
                  );
                },
                label: const Text('Replay mode'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
