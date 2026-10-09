import 'dart:async';

import 'package:flutter/material.dart';

import '../core/contracts.dart' as contracts;
import 'sensing_source.dart';
import 'trace_recorder.dart';

/// Standalone spike screen. Owns and disposes its source, including injected ones.
/// The app owner can open it after granting runtime permissions externally.
class SensingDebugScreen extends StatefulWidget {
  const SensingDebugScreen({super.key, this.source});
  final SensingSource? source;

  @override
  State<SensingDebugScreen> createState() => _SensingDebugScreenState();
}

class _SensingDebugScreenState extends State<SensingDebugScreen> {
  late final SensingSource _source;
  StreamSubscription<Object>? _subscription;
  final _note = TextEditingController();
  int _steps = 0;
  double _lastTurn = 0;
  bool _traceBusy = false;
  String? _message;
  String? _error;

  @override
  void initState() {
    super.initState();
    _source = widget.source ?? SensingSource();
    _subscription = _source.events().listen((event) {
      if (!mounted) return;
      setState(() {
        if (event is contracts.StepEvent) _steps++;
        if (event is contracts.TurnEvent) _lastTurn = event.angle;
      });
    }, onError: (Object error) => _showError(error));
  }

  Future<void> _toggleTrace() async {
    setState(() => _traceBusy = true);
    try {
      if (_source.traceState.value.recording) {
        await _source.stopTrace();
      } else {
        await _startTrace();
      }
    } finally {
      if (mounted) setState(() => _traceBusy = false);
    }
  }

  Future<void> _startTrace() async {
    try {
      await _source.startTrace({
        'map': 'sensing_spike',
        'walker': 'T2',
        'from': 'start',
        'to': 'end',
      });
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (mounted) setState(() => _error = error.toString());
  }

  void _mark() {
    final note = _note.text.trim();
    if (note.isEmpty) {
      setState(() => _message = 'Enter a note before marking.');
      return;
    }
    try {
      _source.mark(note);
      setState(() => _message = 'Marked: $note');
      _note.clear();
    } catch (error) {
      _showError(error);
    }
  }

  @override
  void dispose() {
    _note.dispose();
    unawaited(_cleanup());
    super.dispose();
  }

  Future<void> _cleanup() async {
    try {
      await _subscription?.cancel();
      await _source.dispose();
    } catch (error) {
      debugPrint('Sensing cleanup failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sensing spike')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ValueListenableBuilder<bool?>(
          valueListenable: _source.hardwareStepDetector,
          builder: (_, hardware, _) => Text(
            'Hardware step detector: '
            '${hardware == null
                ? 'waiting'
                : hardware
                ? 'yes'
                : 'no'}',
          ),
        ),
        Text('Steps: $_steps'),
        Text(
          'Last turn: ${_lastTurn >= 0 ? '+' : ''}${_lastTurn.toStringAsFixed(1)}°',
        ),
        const Text('Degrees: left positive (+), right negative (-)'),
        OutlinedButton(
          onPressed: () => setState(() {
            _steps = 0;
            _lastTurn = 0;
          }),
          child: const Text('Reset'),
        ),
        ValueListenableBuilder<TraceState>(
          valueListenable: _source.traceState,
          builder: (_, trace, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(trace.recording ? 'Recording trace' : 'Trace stopped'),
              if (trace.path != null) SelectableText(trace.path!),
              if (trace.error != null)
                Text('Trace write failed: ${trace.error}'),
              FilledButton(
                onPressed: _traceBusy ? null : _toggleTrace,
                child: Text(trace.recording ? 'Stop trace' : 'Start trace'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _note,
                decoration: const InputDecoration(labelText: 'Mark note'),
              ),
              FilledButton(
                onPressed: trace.recording ? _mark : null,
                child: const Text('Mark'),
              ),
            ],
          ),
        ),
        if (_message != null) Text(_message!),
        if (_error != null)
          Text(
            'Sensing unavailable: $_error',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
  );
}
