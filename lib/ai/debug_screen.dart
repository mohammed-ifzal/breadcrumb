/// Gemma debug screen: load time, backend, and the resolved place and answer
/// time for a typed or spoken request or four presets, plus the 40-request
/// benchmark (docs/BENCHMARKS.md).
///
/// `--dart-define=BENCH=reuse|fresh|both` runs the benchmark on its own after
/// loading: 3 rounds, with one reused chat, a new chat per request, or both
/// interleaved round by round. Requests are 2 s apart, like spoken ones.
/// Every result is logged as `BENCH ...`.
library;

import 'package:flutter/material.dart';

import '../core/contracts.dart';
import '../core/place_matcher.dart';
import 'benchmark.dart';
import 'destination_resolver.dart';
import 'gemma_service.dart';
import 'speech_input.dart';

const _autoBench = String.fromEnvironment('BENCH');

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
  final _speech = SpeechInput();
  final _text = TextEditingController();
  final _answers = <_Answer>[];
  String _status = 'Loading Gemma…';
  String _speechStatus = 'Speech: checking…';
  String _benchStatus = '';
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
      debugPrint('BENCH load ${r.loadMs} ms warmup ${r.warmupMs} ms backend ${r.backend}');
    } catch (e) {
      _status = 'Load failed: $e';
    }
    if (mounted) setState(() => _busy = false);
    await _checkSpeech();
    if (_autoBench.isNotEmpty && _gemma.isLoaded) await _bench(_autoBench);
  }

  Future<void> _checkSpeech() async {
    final offline = await _speech.offlineLocales();
    bool has(String id) => offline.any((l) => l.replaceAll('-', '_') == id);
    final status =
        'Speech: on-device supports en-IN ${has(speechLocaleEnglish) ? 'yes' : 'no'}, '
        'hi-IN ${has(speechLocaleHindi) ? 'yes' : 'no'}'
        '${_speech.lastError == null ? '' : ' (${_speech.lastError})'}\n'
        'On-device languages: ${offline.isEmpty ? 'none reported' : offline.join(', ')}';
    debugPrint('BENCH speech $status');
    if (mounted) setState(() => _speechStatus = status);
  }

  Future<void> _listen(String localeId) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _speechStatus = 'Listening ($localeId)…';
    });
    final text = await _speech.listen(localeId: localeId);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _speechStatus = text == null
          ? 'Heard nothing ($localeId)${_speech.lastError == null ? '' : ': ${describeSpeechError(_speech.lastError!)}'}'
          : 'Heard ($localeId): $text';
      _speechStatus += '\n${_speech.lastEvents.join(' | ')}';
    });
    if (text != null) {
      _text.text = text;
      await _ask(text);
    }
  }

  /// [mode]: `reuse`, `fresh` or `both` (interleaved round by round).
  Future<void> _bench(String mode) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _benchStatus = 'Benchmark ($mode) running…';
    });
    final modes = switch (mode) {
      'fresh' => [false],
      'both' => [false, true],
      _ => [true],
    };
    final byMode = {for (final m in modes) m: <BenchResult>[]};
    var done = 0;
    for (var round = 1; round <= 3; round++) {
      for (final reuse in modes) {
        _gemma.reuseChat = reuse;
        final label = reuse ? 'reuse' : 'fresh';
        byMode[reuse]!.addAll(await runBench(
          resolver: _resolver,
          map: debugDemoMap,
          isMatcherHit: (r) => _matcher.match(r, debugDemoMap) != null,
          rounds: 1,
          gap: const Duration(seconds: 2),
          onResult: (r) {
            debugPrint('BENCH r $label $round|${r.toLine()}');
            done++;
            if (mounted) setState(() => _benchStatus = 'Benchmark ($mode): $done done…');
          },
        ));
      }
    }
    _gemma.reuseChat = true;
    final lines = [
      for (final e in byMode.entries)
        '${e.key ? 'reuse' : 'fresh'}: ${BenchSummary(e.value).describe()}',
    ];
    for (final l in lines) {
      debugPrint('BENCH summary $l');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _benchStatus = lines.join('\n');
    });
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
    _speech.cancel();
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
          const SizedBox(height: 8),
          Text(_speechStatus),
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
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.mic),
                  label: const Text('Speak (en-IN)'),
                  onPressed: _busy ? null : () => _listen(speechLocaleEnglish),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.mic),
                  label: const Text('बोलें (hi-IN)'),
                  onPressed: _busy ? null : () => _listen(speechLocaleHindi),
                ),
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
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => _bench('reuse'),
            child: const Text('Benchmark: 40 requests × 3'),
          ),
          if (_benchStatus.isNotEmpty) Text(_benchStatus),
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
