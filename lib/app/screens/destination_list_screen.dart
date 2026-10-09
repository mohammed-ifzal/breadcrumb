import 'package:flutter/material.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'navigate_screen.dart';

class DestinationListScreen extends StatelessWidget {
  const DestinationListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final map = Wiring.instance.map;
    final places = map.places.where((p) => p.kind != PlaceKind.junction).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Select Destination')),
      body: ListView.builder(
        itemCount: places.length,
        itemBuilder: (context, index) {
          final place = places[index];
          return ListTile(
            title: Text(place.name, style: const TextStyle(fontSize: 20)),
            subtitle: place.aliases.isNotEmpty 
              ? Text('Aliases: ${place.aliases.join(", ")}')
              : null,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => NavigateScreen(destinationId: place.id),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
