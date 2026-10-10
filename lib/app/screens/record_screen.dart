import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/contracts.dart' as contracts;
import '../../core/map_builder.dart' as recording;
import '../../core/map_json.dart';
import '../../sensing/sensing_source.dart';
import '../../sensing/trace_recorder.dart';
import '../widgets/trail_view.dart';

/// Saves a finished recording to the D22 location, replacing the previous map.
/// The optional directory lookup allows disk tests without a platform plugin.
Future<String> saveLatestMap(
  contracts.MapGraph map, {
  Future<Directory> Function()? documentsDirectory,
}) async {
  final documents =
      await (documentsDirectory ?? getApplicationDocumentsDirectory)();
  final directory = Directory('${documents.path}${Platform.pathSeparator}maps');
  await directory.create(recursive: true);
  final file = File('${directory.path}${Platform.pathSeparator}latest.json');
  await file.writeAsString(encodeMap(map), flush: true);
  return file.path;
}

/// Return the full path after saving, or throw an error for the screen to display.
typedef RecordMapSave = Future<String> Function(contracts.MapGraph map);

/// Live recording with real defaults and injectable builder/events/persistence.
/// Permissions are granted by the app shell. An injected stream remains owned by
/// its caller; this screen owns and closes only its default sensing source.
class RecordScreen extends StatefulWidget {
  const RecordScreen({
    super.key,
    this.mapBuilder,
    this.events,
    this.save,
    this.traceRecorder,
    this.sensingSource,
  });

  final contracts.MapBuilder? mapBuilder;
  final Stream<Object>? events;
  final RecordMapSave? save;
  final TraceRecorder? traceRecorder;

  /// Injected sources remain caller-owned; their walk trace is stopped here.
  final contracts.SensingSource? sensingSource;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  late final contracts.MapBuilder _builder;
  late final RecordMapSave _save;
  late final TraceRecorder _trace;
  Future<void>? _traceOpening;
  Future<void>? _traceClosing;
  bool _traceReady = false;
  bool _traceFailed = false;
  bool _traceErrorLogged = false;
  String? _traceFailure;
  final _pendingInjected = <Map<String, Object?>>[];
  int _lastInjectedT = 0;
  final _sinceInjected = Stopwatch();
  final _startName = TextEditingController();
  final _placeName = TextEditingController();
  ValueNotifier<contracts.MapGraph>? _map;
  StreamSubscription<Object>? _subscription;
  SensingSource? _ownedSource;
  contracts.SensingSource? get _traceSource =>
      widget.sensingSource ?? _ownedSource;
  bool _floorChanging = false;
  Future<void>? _closingSensors;
  contracts.MapGraph? _finished;
  final _turns = <double>[];
  int _steps = 0;
  int? _stepsAtLastMark;
  bool _started = false;
  bool _recording = false;
  bool _saving = false;
  String? _savedPath;
  String? _saveError;
  String? _sensorError;
  String? _marked;

  @override
  void initState() {
    super.initState();
    _builder = widget.mapBuilder ?? recording.MapBuilder();
    _save = widget.save ?? saveLatestMap;
    _trace = widget.traceRecorder ?? TraceRecorder();
    _trace.state.addListener(_onTraceState);
  }

  void _start() {
    final name = _startName.text.trim();
    if (_started || name.isEmpty) return;
    try {
      _builder.start(name);
      // D19: start must precede the very first snapshot.
      _map = ValueNotifier(_builder.snapshot());
      setState(() {
        _started = true;
        _recording = true;
        _sensorError = null;
      });
      _sinceInjected.start();
      if (widget.events == null && widget.sensingSource == null) {
        _ownedSource = SensingSource(recorder: _trace);
      }
      _traceOpening = _beginTrace(name);
      final events = widget.events ?? _traceSource!.events();
      _subscription = events.listen(
        _onEvent,
        onError: _onSensorError,
        onDone: () {
          if (!mounted || !_recording) return;
          setState(() {
            _recording = false;
            _sensorError =
                'Sensor stream ended. Stop to save the trail recorded so far.';
          });
        },
      );
    } catch (error) {
      _onSensorError(error);
    }
  }

  void _onEvent(Object event) {
    if (!mounted || !_recording) return;
    try {
      if (event is contracts.StepEvent) {
        _builder.onStep(event);
        _steps++;
        if (widget.events != null) {
          _lastInjectedT = event.t;
          _sinceInjected
            ..reset()
            ..start();
          _writeInjectedTrace({'type': 'step', 't': event.t});
        }
      } else if (event is contracts.TurnEvent) {
        _builder.onTurn(event);
        _turns.add(event.angle);
      } else {
        return;
      }
      _map!.value = _builder.snapshot();
      setState(() {});
    } catch (error) {
      _onSensorError(error);
    }
  }

  void _onSensorError(Object error) {
    if (mounted) setState(() => _sensorError = error.toString());
  }

  void _mark() {
    final name = _placeName.text.trim();
    if (!_recording || name.isEmpty) return;
    try {
      _builder.addPlace(name, const []);
      _stepsAtLastMark = _steps;
      _traceMark(name);
      _map!.value = _builder.snapshot();
      _placeName.clear();
      setState(() => _marked = 'Marked place: $name');
    } catch (error) {
      _onSensorError(error);
    }
  }

  Future<void> _stop() async {
    if (!_started || _saving || _savedPath != null) return;
    setState(() {
      _recording = false;
      _saving = true;
      _saveError = null;
    });
    try {
      // Keep the same finished map for a retry; stop accepting sensor events
      // immediately so neither delayed events nor retries add steps.
      if (_finished == null) {
        // D23: retain a just-marked final position instead of adding another
        // place at zero distance. Otherwise make the endpoint selectable.
        if (_stepsAtLastMark != _steps) {
          _builder.addPlace('End of walk', const []);
          _stepsAtLastMark = _steps;
          _traceMark('End of walk');
          _map!.value = _builder.snapshot();
        }
        _finished = _builder.finish();
      }
      _map!.value = _finished!;
      // Persistence must not wait on platform stream teardown.
      unawaited(_releaseSensors());
      final path = await _save(_finished!);
      if (mounted) setState(() => _savedPath = path);
    } catch (error) {
      if (mounted) setState(() => _saveError = 'Could not save map: $error');
    } finally {
      await _stopWalkTrace();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeFloor() async {
    final builder = _builder;
    if (!_recording || _floorChanging || builder is! recording.MapBuilder) {
      return;
    }
    setState(() => _floorChanging = true);
    try {
      final delta = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Change floor'),
          content: const Text('Which direction?'),
          actions: [
            TextButton(
              key: const ValueKey('floor-cancel'),
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const ValueKey('floor-down'),
              onPressed: () => Navigator.pop(context, -1),
              child: const Text('Down'),
            ),
            TextButton(
              key: const ValueKey('floor-up'),
              onPressed: () => Navigator.pop(context, 1),
              child: const Text('Up'),
            ),
          ],
        ),
      );
      if (!mounted || !_recording || delta == null) return;
      final kind = await showDialog<contracts.CorridorKind>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Choose transport'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final kind in [
                contracts.CorridorKind.stairs,
                contracts.CorridorKind.escalator,
                contracts.CorridorKind.lift,
              ])
                TextButton(
                  key: ValueKey('floor-${kind.name}'),
                  onPressed: () => Navigator.pop(context, kind),
                  child: Text(
                    '${kind.name[0].toUpperCase()}${kind.name.substring(1)}',
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              key: const ValueKey('floor-cancel'),
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      if (!mounted || !_recording || kind == null) return;
      final from = _map!.value.places.last.floor;
      builder.changeFloor(delta, kind);
      // A floor transition moves away from a previously marked position even
      // without horizontal steps; D23 must add the endpoint on the new floor.
      _stepsAtLastMark = null;
      _map!.value = builder.snapshot();
      _traceMark(
        'Floor change: ${delta > 0 ? 'up' : 'down'} via ${kind.name} (Floor $from -> Floor ${from + delta})',
      );
      setState(() {});
    } catch (error) {
      _onSensorError(error);
    } finally {
      if (mounted) setState(() => _floorChanging = false);
    }
  }

  void _onTraceState() {
    if (_trace.state.value.error != null) _traceFailed = true;
    if (mounted) setState(() {});
  }

  void _traceError(Object error) {
    _traceFailed = true;
    _pendingInjected.clear();
    // TraceRecorder logs its own I/O errors; don't log those again here.
    if (!_traceErrorLogged && _trace.state.value.error == null) {
      _traceErrorLogged = true;
      debugPrint('Trace recording failed: $error');
    }
    if (mounted) setState(() => _traceFailure = error.toString());
  }

  Future<void> _beginTrace(String name) async {
    final meta = <String, Object?>{
      'map': name,
      'walker': 'record',
      'from': _map!.value.start,
    };
    try {
      final source = _traceSource;
      if (source != null) {
        await source.startTrace(meta);
      } else {
        // Injected derived events cannot provide gyro samples. Do not invent
        // hardware provenance or motion; these traces are explicitly labelled.
        await _trace.start({
          ...meta,
          'eventSource': 'injected-events',
          'motionReplayable': false,
        });
      }
      _traceReady =
          widget.sensingSource != null || _trace.state.value.recording;
      final pending = List<Map<String, Object?>>.of(_pendingInjected);
      _pendingInjected.clear();
      if (_traceReady) {
        for (final row in pending) {
          _trace.record(row);
        }
      }
    } catch (error) {
      _traceError(error);
    }
  }

  void _writeInjectedTrace(Map<String, Object?> row) {
    if (_traceFailed) return;
    try {
      if (!_traceReady) {
        _pendingInjected.add(Map.of(row));
      } else {
        _trace.record(row);
      }
    } catch (error) {
      _traceError(error);
    }
  }

  void _traceMark(String note) {
    if (_traceFailed) return;
    try {
      final source = _traceSource;
      if (source != null) {
        source.mark(note);
      } else {
        _writeInjectedTrace({
          'type': 'mark',
          't': _lastInjectedT + _sinceInjected.elapsedMilliseconds,
          'note': note,
        });
      }
    } catch (error) {
      _traceError(error);
    }
  }

  Future<void> _stopWalkTrace() => _traceClosing ??= _finishTrace();
  Future<void> _finishTrace() async {
    try {
      await _traceOpening;
      final source = _traceSource;
      if (source != null) {
        await source.stopTrace();
      } else {
        await _trace.stop();
      }
      if (!_traceFailed && widget.sensingSource == null) {
        final places = _finished?.places
            .where((p) => p.kind == contracts.PlaceKind.place)
            .toList();
        await _trace.finalizeMetadata({
          'completed': _finished != null,
          'mapSaved': _savedPath != null,
          if (places != null && places.isNotEmpty) 'to': places.last.id,
        });
      }
    } catch (error) {
      _traceError(error);
    }
  }

  Future<void> _releaseSensors() => _closingSensors ??= _closeSensors();

  Future<void> _closeSensors() async {
    final subscription = _subscription;
    _subscription = null;
    final cancelled = subscription?.cancel();
    await _stopWalkTrace();
    try {
      await cancelled;
    } catch (error) {
      debugPrint('Record subscription cleanup failed: $error');
    }
    try {
      await _ownedSource?.dispose();
    } catch (error) {
      debugPrint('Record sensing cleanup failed: $error');
    }
  }

  @override
  void dispose() {
    _recording = false;
    unawaited(_releaseSensors());
    _trace.state.removeListener(_onTraceState);
    _sinceInjected.stop();
    if (widget.traceRecorder == null) {
      unawaited(_disposeTrace());
    }
    _startName.dispose();
    _placeName.dispose();
    _map?.dispose();
    super.dispose();
  }

  Future<void> _disposeTrace() async {
    await _releaseSensors();
    await _trace.dispose();
  }

  String _formatTurn(double angle) =>
      '${angle >= 0 ? '+' : ''}${angle.toStringAsFixed(1)}° '
      '(${angle >= 0 ? 'left' : 'right'})';

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Record a trail')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_started) ...[
                    Text(
                      'Where does your trail start?',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('start-name'),
                      controller: _startName,
                      decoration: const InputDecoration(
                        labelText: 'Start place name',
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _start(),
                    ),
                    const SizedBox(height: 12),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _startName,
                      builder: (_, value, _) => FilledButton(
                        key: const ValueKey('record-start'),
                        onPressed: value.text.trim().isEmpty ? null : _start,
                        child: const Text('Start'),
                      ),
                    ),
                  ],
                  if (_started) ...[
                    Text(
                      _recording ? 'Recording trail' : 'Recording stopped',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    AnimatedSwitcher(
                      duration: duration,
                      child: Text(
                        'Steps: $_steps',
                        key: ValueKey(_steps),
                        style: theme.textTheme.headlineMedium,
                      ),
                    ),
                    Text(
                      _turns.isEmpty
                          ? 'Last turn: none'
                          : 'Last turn: ${_formatTurn(_turns.last)}',
                    ),
                    Text(
                      'Current floor: ${_map!.value.places.last.floor}',
                      key: const ValueKey('current-floor'),
                    ),
                    if (_recording)
                      OutlinedButton.icon(
                        key: const ValueKey('record-floor'),
                        onPressed:
                            _floorChanging || _builder is! recording.MapBuilder
                            ? null
                            : _changeFloor,
                        icon: const Icon(Icons.swap_vert),
                        label: const Text('Change floor'),
                      ),
                    if (_turns.length > 1) ...[
                      const Text('Recent turns, newest first:'),
                      for (final angle in _turns.reversed.take(3))
                        Text(_formatTurn(angle)),
                    ],
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: ColoredBox(
                        color: theme.colorScheme.surfaceContainerLow,
                        // A proportional canvas bounds TrailView's infinite
                        // CustomPaint size inside the scroll view; no fixed height.
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: TrailView(mapNotifier: _map!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _finished == null
                          ? 'Your current position is the red dot.'
                          : 'Your recorded trail.',
                    ),
                    if (_recording) ...[
                      const SizedBox(height: 16),
                      TextField(
                        key: const ValueKey('place-name'),
                        controller: _placeName,
                        decoration: const InputDecoration(
                          labelText: 'Place name',
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _mark(),
                      ),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _placeName,
                        builder: (_, value, _) => FilledButton(
                          key: const ValueKey('record-mark'),
                          onPressed: value.text.trim().isEmpty ? null : _mark,
                          child: const Text('Mark place'),
                        ),
                      ),
                    ],
                    if (_marked != null) Text(_marked!),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const ValueKey('record-stop'),
                      onPressed: _saving || _savedPath != null ? null : _stop,
                      child: Text(
                        _saving
                            ? 'Saving map…'
                            : _saveError != null
                            ? 'Retry save'
                            : 'Stop',
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: duration,
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: _savedPath == null
                          ? const SizedBox.shrink()
                          : SelectableText(
                              'Saved map: $_savedPath',
                              key: ValueKey(_savedPath),
                            ),
                    ),
                    ValueListenableBuilder<TraceState>(
                      valueListenable: _trace.state,
                      builder: (_, trace, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (trace.path != null)
                            SelectableText('Trace file: ${trace.path}'),
                          if (trace.error != null || _traceFailure != null)
                            Text(
                              'Trace unavailable: ${trace.error ?? _traceFailure}. Map recording continues.',
                            ),
                        ],
                      ),
                    ),
                    if (_saveError != null)
                      Text(
                        _saveError!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                  ],
                  if (_sensorError != null)
                    Text(
                      'Sensing error: $_sensorError',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
