import 'package:flutter/material.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'navigate_screen.dart';

class DestinationListScreen extends StatefulWidget {
  const DestinationListScreen({super.key});

  @override
  State<DestinationListScreen> createState() => _DestinationListScreenState();
}

class _DestinationListScreenState extends State<DestinationListScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isThinking = false;
  String? _feedbackMessage;
  int _latestRequestId = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged(String _) {
    // If the user types again, cancel thinking and ignore any pending late answer
    _latestRequestId++;
    if (_isThinking || _feedbackMessage != null) {
      setState(() {
        _isThinking = false;
        _feedbackMessage = null;
      });
    }
  }

  Future<void> _submit() async {
    final utterance = _controller.text.trim();
    if (utterance.isEmpty || _isThinking) return;

    final requestId = ++_latestRequestId;
    setState(() {
      _isThinking = true;
      _feedbackMessage = null;
    });

    final wiring = Wiring.instance;
    final map = wiring.map;
    final currentPlace = wiring.effectiveCurrentPlaceId;

    PlaceMatch? match;
    try {
      match = await wiring.destinationResolver.resolve(utterance, map);
    } catch (_) {
      match = null;
    }

    if (!mounted || requestId != _latestRequestId) return;

    final targetId = match?.placeId;
    final isValid = targetId != null &&
        map.places.any((p) =>
            p.id == targetId &&
            p.kind != PlaceKind.junction &&
            p.id != currentPlace);

    if (isValid) {
      setState(() {
        _isThinking = false;
      });
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => NavigateScreen(destinationId: targetId),
        ),
      );
    } else {
      setState(() {
        _isThinking = false;
        _feedbackMessage = "Didn't catch that, pick from the list";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final map = Wiring.instance.map;
    final currentPlace = Wiring.instance.effectiveCurrentPlaceId;
    final places = map.places
        .where((p) => p.kind != PlaceKind.junction && p.id != currentPlace)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Select Destination')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        onChanged: _onTextChanged,
                        onSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          hintText: 'Where do you want to go?',
                          labelText: 'Where do you want to go?',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Empty slot or disabled placeholder for mic button
                    const IconButton(
                      icon: Icon(Icons.mic_off),
                      onPressed: null,
                      tooltip: 'Voice input placeholder',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _isThinking ? null : _submit,
                  child: _isThinking
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('Thinking...'),
                          ],
                        )
                      : const Text('Submit'),
                ),
                if (_feedbackMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _feedbackMessage!,
                    style: TextStyle(
                      color: Colors.amber.shade900,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
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
          ),
        ],
      ),
    );
  }
}
