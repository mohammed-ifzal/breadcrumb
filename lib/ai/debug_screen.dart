/// Gemma spike screen (docs/PROMPTS.md, Ifzal prompt 3): load time, backend, and
/// the resolved place and answer time for a typed request or four presets.
library;

import 'package:flutter/material.dart';

import '../core/contracts.dart';
import '../core/place_matcher.dart';
import 'destination_resolver.dart';
import 'gemma_service.dart';

/// Same as `demoMap` in test/core/test_maps.dart (lib/ can't import test/).
const debugDemoMap = MapGraph(
  name: 'Table loop',
  start: 'start',
  places: [
    Place(id: 'start', name: 'Start', kind: PlaceKind.start),
    Place(id: 'j1', name: 'Junction 1', kind: PlaceKind.junction),
    Place(
      id: 'food_counter',
      name: 'Food counter',
      aliases: ['canteen', 'खाना काउंटर'],
      kind: PlaceKind.place,
    ),
    Place(id: 'j2', name: 'Junction 2', kind: PlaceKind.junction),
    Place(id: 'stage_side', name: 'Stage side', kind: PlaceKind.place),
  ],
  corridors: [
    Corridor(id: 'c1', from: 'start', to: 'j1', steps: 12, heading: 0),
    Corridor(id: 'c2', from: 'j1', to: 'food_counter', steps: 10, heading: 90),
    Corridor(id: 'c3', from: 'food_counter', to: 'j2', steps: 8, heading: 90),
    Corridor(id: 'c4', from: 'j2', to: 'stage_side', steps: 6, heading: 0),
  ],
);

const debugPresets = [
  'where can I get coffee',
  'take me back to the stage',
  'मुझे खाने की जगह जाना है',
  'take me to the moon',
];

class GemmaDebugScreen extends StatefulWidget {
  const GemmaDebugScreen({super.key});

  @override
  State<GemmaDebugScreen> createState() => _GemmaDebugScreenState();
}

class _Answer {
  const _Answer(this.request, this.result, this.ms);

  final String request;
  final String result;
  final int ms;
}

class _GemmaDebugScreenState extends State<GemmaDebugScreen> {
  final _gemma = GemmaService();
  final _matcher = FuzzyPlaceMatcher();
  late final _resolver = GemmaDestinationResolver(matcher: _matcher, chooser: _gemma);
  final _text = TextEditingController();
  final _answers = <_Answer>[];
  String _status = 'Loading Gemma…';
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _gemma.load();
      _status =
          'Loaded in ${r.loadMs} ms (+ warm-up ${r.warmupMs} ms)\n'
          'Backend: ${r.backend}\nPath: ${r.path}'
          '${r.notes.isEmpty ? '' : '\nNotes: ${r.notes.join('\n')}'}';
    } catch (e) {
      _status = 'Load failed: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _ask(String request) async {
    if (request.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    final watch = Stopwatch()..start();
    final fuzzy = _matcher.match(request, debugDemoMap);
    final match = await _resolver.resolve(request, debugDemoMap);
    final ms = watch.elapsedMilliseconds;
    String result;
    if (match == null) {
      result = 'null (no place)';
    } else {
      final name = debugDemoMap.places.firstWhere((p) => p.id == match.placeId).name;
      final via = fuzzy != null ? 'PlaceMatcher' : 'Gemma';
      result = '$name (${match.placeId}) via $via';
    }
    if (!mounted) return;
    setState(() {
      _answers.insert(0, _Answer(request, result, ms));
      _busy = false;
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _gemma.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gemma debug')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_status),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  decoration: const InputDecoration(hintText: 'Where to?'),
                  onSubmitted: _ask,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: _busy ? null : () => _ask(_text.text),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final preset in debugPresets)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(
                onPressed: _busy ? null : () => _ask(preset),
                child: Text(preset),
              ),
            ),
          if (_busy) const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          const Divider(height: 32),
          for (final a in _answers)
            ListTile(
              title: Text(a.request),
              subtitle: Text('${a.result}\n${a.ms} ms'),
              isThreeLine: true,
            ),
        ],
      ),
    );
  }
}
