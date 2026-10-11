import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../ai/alias_suggester.dart';
import '../../core/contracts.dart' as contracts;
import '../../core/map_builder.dart' as recording;
import '../../core/tuning.dart'
    show straightTolerance, turnAroundAngle, useTurnConfirmer;
import '../../core/turn_confirmer.dart' show confirmedEvents;
import '../../sensing/sensing_source.dart';
import '../../sensing/trace_recorder.dart';
import '../map_library.dart';
import '../theme.dart';
import '../widgets/trail_view.dart';
import '../widgets/ui/ui.dart';
import '../wiring.dart';

/// D33: saves a finished recording as a new map in the [MapLibrary] and makes
/// it the active map; older maps are kept. The optional directory lookup
/// allows disk tests without a platform plugin.
Future<String> saveRecordedMap(
  contracts.MapGraph map, {
  Future<Directory> Function()? documentsDirectory,
}) async {
  final saved = await MapLibrary(documentsDirectory: documentsDirectory)
      .save(map);
  return saved.path;
}

/// The walk so far, oldest first, from the recorded corridors in walk order:
/// the start, then per corridor its turn ("Left", "Right", "U-turn"; turns are
/// already snapped), its steps ("45 steps") or floor change ("Stairs up"),
/// and the place it ends at. Real data only; display text, not logic.
List<String> trailTimeline(contracts.MapGraph map) {
  final places = {for (final p in map.places) p.id: p};
  final items = <String>[];
  final start = places[map.start];
  if (start != null) items.add(start.name);
  contracts.Corridor? previous;
  for (final c in map.corridors) {
    if (previous != null && !previous.isTransition && !c.isTransition) {
      final turn = contracts.turnBetween(previous.heading, c.heading);
      if (turn.abs() > turnAroundAngle) {
        items.add('U-turn');
      } else if (turn.abs() >= straightTolerance) {
        items.add(turn > 0 ? 'Left' : 'Right');
      }
    }
    if (c.isTransition) {
      final kind = '${c.kind.name[0].toUpperCase()}${c.kind.name.substring(1)}';
      items.add('$kind ${c.floorDelta > 0 ? 'up' : 'down'}');
    } else if (c.steps > 0) {
      items.add(c.steps == 1 ? '1 step' : '${c.steps} steps');
    }
    final end = places[c.to];
    if (end != null &&
        end.id != contracts.hereId &&
        end.kind != contracts.PlaceKind.junction) {
      items.add(end.name);
    }
    previous = c;
  }
  return items;
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
    this.aliasSuggester,
  });

  final contracts.MapBuilder? mapBuilder;
  final Stream<Object>? events;
  final RecordMapSave? save;
  final TraceRecorder? traceRecorder;

  /// Injected sources remain caller-owned; their walk trace is stopped here.
  final contracts.SensingSource? sensingSource;

  /// D30: suggests aliases after "Mark place". Null: Gemma on the full tier,
  /// none on the basic tier (decided at each mark).
  final AliasSuggester? aliasSuggester;

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
  final _aliasesById = <String, List<String>>{};

  /// Step count at each mark still undoable, oldest first (for D23).
  final _markSteps = <int?>[];
  bool _asking = false;

  /// Display only: time since Start, refreshed once a second while recording.
  final _clock = Stopwatch();
  Timer? _clockTick;

  @override
  void initState() {
    super.initState();
    _builder = widget.mapBuilder ?? recording.MapBuilder();
    _save = widget.save ?? saveRecordedMap;
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
      _clock.start();
      _clockTick = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || !_recording) {
          _clock.stop();
          timer.cancel();
        }
        if (mounted) setState(() {});
      });
      if (widget.events == null && widget.sensingSource == null) {
        _ownedSource = SensingSource(recorder: _trace);
      }
      _traceOpening = _beginTrace(name);
      // D29: with useTurnConfirmer the MapBuilder sees the same confirmed turns
      // as the Tracker in Navigate.
      final events =
          widget.events ??
          (useTurnConfirmer
              ? confirmedEvents(_traceSource!)
              : _traceSource!.events());
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

  contracts.Place? _existingPlace(String name) {
    final key = name.trim().toLowerCase();
    for (final place in _map!.value.places) {
      if (place.kind != contracts.PlaceKind.junction &&
          place.name.trim().toLowerCase() == key) {
        return place;
      }
    }
    return null;
  }

  Future<void> _finishAtStart() async {
    if (!_started || _saving || _finished != null) return;
    final map = _map!.value;
    final start = map.places.firstWhere((place) => place.id == map.start);
    if (!await _confirm(
      key: 'finish',
      title: 'Finish at ${start.name}?',
      body: 'This joins the loop at ${start.name} and saves the map.',
      yes: 'Finish and save',
    )) {
      return;
    }
    if (!mounted || !_recording) return;
    try {
      _builder.addPlace(start.name, const []);
      _stepsAtLastMark = _steps;
      _map!.value = _builder.snapshot();
      _traceMark(start.name);
      setState(() => _marked = 'Joined to ${start.name} - loop closed');
      await _stop(confirmed: true);
    } catch (error) {
      _onSensorError(error);
    }
  }

  /// A yes/no dialog; true only on the yes button. Buttons have keys
  /// `<key>-yes` and `<key>-no`.
  Future<bool> _confirm({
    required String key,
    required String title,
    required String body,
    required String yes,
    String no = 'Keep recording',
  }) async {
    if (_asking) return false;
    _asking = true;
    try {
      final answer = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              key: ValueKey('$key-no'),
              onPressed: () => Navigator.pop(context, false),
              child: Text(no),
            ),
            FilledButton(
              key: ValueKey('$key-yes'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(yes),
            ),
          ],
        ),
      );
      return answer ?? false;
    } finally {
      _asking = false;
    }
  }

  /// [name] with the lowest free " 2", " 3"... suffix among marked places.
  String _freeName(String name) {
    for (var n = 2; ; n++) {
      final candidate = '$name $n';
      if (_existingPlace(candidate) == null) return candidate;
    }
  }

  Future<void> _mark() async {
    var name = _placeName.text.trim();
    if (!_recording || name.isEmpty || _asking) return;
    final existing = _existingPlace(name);
    if (existing != null) {
      // A wrong silent join would bend the whole trail, so ask first.
      final join = await _confirm(
        key: 'join',
        title: 'Join the loop?',
        body:
            "A place called '${existing.name}' already exists. "
            'Connect this point to it?',
        yes: 'Join loop',
        no: "Save as '${_freeName(existing.name)}'",
      );
      if (!mounted || !_recording) return;
      if (!join) name = _freeName(existing.name);
    }
    try {
      final joined = _existingPlace(name);
      final builder = _builder;
      final marksBefore = builder is recording.MapBuilder
          ? builder.undoableMarks
          : 0;
      _builder.addPlace(name, const []);
      if (builder is recording.MapBuilder &&
          builder.undoableMarks > marksBefore) {
        _markSteps.add(_stepsAtLastMark);
      }
      _stepsAtLastMark = _steps;
      _traceMark(name);
      final snapshot = _builder.snapshot();
      _map!.value = snapshot;
      if (joined == null) unawaited(_suggestAliases(name, snapshot.places));
      _placeName.clear();
      setState(
        () => _marked = joined == null
            ? 'Marked place: $name'
            : 'Joined to ${joined.name} - loop closed',
      );
    } catch (error) {
      _onSensorError(error);
    }
  }

  void _undoMark() {
    final builder = _builder;
    if (!_recording || builder is! recording.MapBuilder) return;
    try {
      final before = _map!.value.places.map((p) => p.id).toSet();
      final undone = builder.undoLastMark();
      if (undone == null) return;
      _stepsAtLastMark = _markSteps.isEmpty ? null : _markSteps.removeLast();
      final snapshot = builder.snapshot();
      // Aliases belong to the place; a place turned into a junction loses them.
      for (final id in before) {
        final place = snapshot.places.where((p) => p.id == id);
        if (place.isEmpty || place.first.kind == contracts.PlaceKind.junction) {
          _aliasesById.remove(id);
        }
      }
      _map!.value = snapshot;
      _traceMark('Undo mark: $undone');
      setState(() => _marked = 'Removed mark: $undone');
    } catch (error) {
      _onSensorError(error);
    }
  }

  bool get _canUndo {
    final builder = _builder;
    return _recording &&
        builder is recording.MapBuilder &&
        builder.undoableMarks > 0;
  }

  Future<void> _stop({bool confirmed = false}) async {
    if (!_started || _saving || _savedPath != null) return;
    if (!confirmed && _finished == null) {
      final stop = await _confirm(
        key: 'stop',
        title: 'Stop and save this map?',
        body: 'Recording ends here. Older maps stay in Saved maps.',
        yes: 'Stop and save',
      );
      if (!stop || !mounted || _saving || _savedPath != null) return;
    }
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
        // D30: aliases that arrived by now; a late reply is dropped.
        _finished = applyAliases(_builder.finish(), _aliasesById);
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

  /// D30: asks for aliases in the background. Nothing on the basic tier, an
  /// error or a timeout; the walk never waits for it.
  Future<void> _suggestAliases(
    String name,
    List<contracts.Place> places,
  ) async {
    final marked = places.where(
      (p) => p.name == name && p.kind != contracts.PlaceKind.junction,
    );
    if (marked.isEmpty) return;
    final id = marked.last.id;
    final wiring = Wiring.instance;
    final suggester =
        widget.aliasSuggester ??
        AliasSuggester(
          model: wiring.aiStatus.value.tier == contracts.DeviceTier.full
              ? wiring.gemmaService
              : null,
        );
    if (suggester.model == null) return;
    try {
      final aliases = await suggester.suggest(name, places);
      if (aliases.isNotEmpty && _finished == null) _aliasesById[id] = aliases;
    } catch (_) {
      // Aliases are optional; the place is already marked.
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
          if (places != null && places.isNotEmpty)
            'to': _finished!.corridors.isEmpty
                ? _finished!.start
                : _finished!.corridors.last.to,
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
    _clockTick?.cancel();
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

  static String _formatElapsed(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final sec = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
  }

  /// Secondary style for a [FilledButton], so Stop keeps its widget type.
  static final ButtonStyle _secondaryFilled = FilledButton.styleFrom(
    backgroundColor: BreadcrumbTheme.surface2,
    foregroundColor: BreadcrumbTheme.textPrimary,
    disabledBackgroundColor: BreadcrumbTheme.surface2,
    disabledForegroundColor: BreadcrumbTheme.textMuted,
    side: const BorderSide(color: BreadcrumbTheme.borderActive),
    minimumSize: const Size(BreadcrumbTheme.minTouch, BreadcrumbTheme.minTouch),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    shape: const RoundedRectangleBorder(
      borderRadius: BreadcrumbTheme.borderRadius,
    ),
    textStyle: BreadcrumbTheme.button,
  );

  Widget _statCard({
    required String label,
    required Widget value,
    Widget? action,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: BreadcrumbTheme.surface1,
        borderRadius: BreadcrumbTheme.borderRadius,
        border: Border.fromBorderSide(
          BorderSide(color: BreadcrumbTheme.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, style: BreadcrumbTheme.eyebrow),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: value,
          ),
          if (action != null) ...[
            const Spacer(),
            const SizedBox(height: 8),
            action,
          ],
        ],
      ),
    );
  }

  static const _bigNumber = TextStyle(
    fontFamily: BreadcrumbTheme.fontFamily,
    fontSize: 36,
    fontWeight: FontWeight.w700,
    height: 1.1,
    letterSpacing: -0.5,
    color: BreadcrumbTheme.textPrimary,
    fontFeatures: BreadcrumbTheme.tabular,
  );

  Widget _timeline(contracts.MapGraph map) {
    final items = trailTimeline(map);
    final shown = items.length > 7 ? items.sublist(items.length - 7) : items;
    const turns = {'Left', 'Right', 'U-turn'};
    return SizedBox(
      height: 40,
      child: SingleChildScrollView(
        key: const ValueKey('record-timeline'),
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(
          children: [
            if (shown.length < items.length)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Text('…', style: BreadcrumbTheme.secondary),
              ),
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: BreadcrumbTheme.textMuted,
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: turns.contains(shown[i])
                      ? BreadcrumbTheme.surface3
                      : BreadcrumbTheme.surface1,
                  borderRadius: BreadcrumbTheme.borderRadiusSm,
                  border: Border.all(
                    color: turns.contains(shown[i])
                        ? BreadcrumbTheme.borderActive
                        : BreadcrumbTheme.border,
                  ),
                ),
                child: Text(
                  shown[i],
                  style: turns.contains(shown[i])
                      ? BreadcrumbTheme.secondary.copyWith(
                          color: BreadcrumbTheme.accent,
                          fontWeight: FontWeight.w600,
                        )
                      : shown[i].endsWith(' steps') ||
                            shown[i].endsWith(' step')
                      ? BreadcrumbTheme.secondary.copyWith(
                          fontFeatures: BreadcrumbTheme.tabular,
                        )
                      : BreadcrumbTheme.secondary.copyWith(
                          color: BreadcrumbTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    if (!_recording && _clock.isRunning) _clock.stop();
    final trailHeight = (MediaQuery.sizeOf(context).height * 0.42).clamp(
      240.0,
      480.0,
    );
    // Leaving mid-walk would lose it, so Back asks first.
    final unsaved = _started && _savedPath == null && !_saving;
    return PopScope(
      canPop: !unsaved,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirm(
          key: 'discard',
          title: 'Discard this recording?',
          body: 'The walk is not saved. Saved maps are not affected.',
          yes: 'Discard',
        );
        // Navigator.pop is not blocked by canPop; only Back is.
        if (discard && mounted) Navigator.of(this.context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Record a trail')),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!_started) ...[
                            const Text(
                              'Where does your trail start?',
                              style: BreadcrumbTheme.headline,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Hold the phone in your hand, screen up, and walk at a normal pace. '
                              'Mark places as you pass them.',
                              style: BreadcrumbTheme.secondary,
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              key: const ValueKey('start-name'),
                              controller: _startName,
                              decoration: const InputDecoration(
                                labelText: 'Start place name',
                              ),
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _start(),
                            ),
                            const SizedBox(height: 16),
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _startName,
                              builder: (_, value, _) => PressScale(
                                child: FilledButton(
                                  key: const ValueKey('record-start'),
                                  onPressed: value.text.trim().isEmpty
                                      ? null
                                      : _start,
                                  child: const Text('Start'),
                                ),
                              ),
                            ),
                          ],
                          if (_started) ...[
                            // Header: recording light, state and the real elapsed time.
                            Row(
                              children: [
                                PulsingDot(
                                  color: _recording
                                      ? BreadcrumbTheme.recording
                                      : BreadcrumbTheme.textMuted,
                                  active: _recording,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      _recording ? 'RECORDING' : 'STOPPED',
                                      style: BreadcrumbTheme.eyebrow.copyWith(
                                        fontSize: 13,
                                        color: _recording
                                            ? BreadcrumbTheme.recording
                                            : BreadcrumbTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      _formatElapsed(_clock.elapsed),
                                      key: const ValueKey('record-elapsed'),
                                      style: BreadcrumbTheme.title.copyWith(
                                        fontFeatures: BreadcrumbTheme.tabular,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _statCard(
                                      label: 'STEPS',
                                      value: Text(
                                        '$_steps',
                                        key: const ValueKey('record-steps'),
                                        style: _bigNumber,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _statCard(
                                      label: 'FLOOR',
                                      value: Text(
                                        'Current floor: ${_map!.value.places.last.floor}',
                                        key: const ValueKey('current-floor'),
                                        style: BreadcrumbTheme.title.copyWith(
                                          fontFeatures: BreadcrumbTheme.tabular,
                                        ),
                                      ),
                                      action: _recording
                                          ? SizedBox(
                                              width: double.infinity,
                                              child: OutlinedButton.icon(
                                                key: const ValueKey(
                                                  'record-floor',
                                                ),
                                                onPressed:
                                                    _floorChanging ||
                                                        _builder
                                                            is! recording.MapBuilder
                                                    ? null
                                                    : _changeFloor,
                                                style: OutlinedButton.styleFrom(
                                                  minimumSize: const Size(
                                                    48,
                                                    48,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                      ),
                                                ),
                                                icon: const Icon(
                                                  Icons.swap_vert_rounded,
                                                  size: 20,
                                                ),
                                                label: const FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Text('Change floor'),
                                                ),
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            ValueListenableBuilder<contracts.MapGraph>(
                              valueListenable: _map!,
                              builder: (_, map, _) => _timeline(map),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: trailHeight,
                              child: DecoratedBox(
                                position: DecorationPosition.foreground,
                                decoration: const BoxDecoration(
                                  borderRadius: BreadcrumbTheme.borderRadiusLg,
                                  border: Border.fromBorderSide(
                                    BorderSide(color: BreadcrumbTheme.border),
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BreadcrumbTheme.borderRadiusLg,
                                  child: TrailView(mapNotifier: _map!),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _finished == null
                                  ? 'The white dot is you.'
                                  : 'Your recorded trail.',
                              style: BreadcrumbTheme.caption,
                            ),
                            if (_marked != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _marked!,
                                style: BreadcrumbTheme.body.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            AnimatedSwitcher(
                              duration: duration,
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                              child: _savedPath == null
                                  ? const SizedBox.shrink()
                                  : Padding(
                                      key: ValueKey(_savedPath),
                                      padding: const EdgeInsets.only(top: 8),
                                      child: SelectableText(
                                        'Saved map: $_savedPath',
                                        style: BreadcrumbTheme.secondary
                                            .copyWith(
                                              color: BreadcrumbTheme.success,
                                            ),
                                      ),
                                    ),
                            ),
                            ValueListenableBuilder<TraceState>(
                              valueListenable: _trace.state,
                              builder: (_, trace, _) => Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (trace.path != null)
                                    SelectableText(
                                      'Trace file: ${trace.path}',
                                      style: BreadcrumbTheme.caption,
                                    ),
                                  if (trace.error != null ||
                                      _traceFailure != null)
                                    Text(
                                      'Trace unavailable: ${trace.error ?? _traceFailure}. Map recording continues.',
                                      style: BreadcrumbTheme.caption,
                                    ),
                                ],
                              ),
                            ),
                            if (_saveError != null)
                              Text(
                                _saveError!,
                                style: BreadcrumbTheme.secondary.copyWith(
                                  color: BreadcrumbTheme.error,
                                ),
                              ),
                          ],
                          if (_sensorError != null)
                            Text(
                              'Sensing error: $_sensorError',
                              style: BreadcrumbTheme.secondary.copyWith(
                                color: BreadcrumbTheme.error,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_started)
                // Bottom tray: name, Mark place, then the secondary actions.
                Container(
                  decoration: const BoxDecoration(
                    color: BreadcrumbTheme.surface1,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(BreadcrumbTheme.radiusLg),
                    ),
                    border: Border(
                      top: BorderSide(color: BreadcrumbTheme.border),
                    ),
                  ),
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_recording) ...[
                          TextField(
                            key: const ValueKey('place-name'),
                            controller: _placeName,
                            decoration: const InputDecoration(
                              labelText: 'Place name',
                            ),
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _mark(),
                          ),
                          const SizedBox(height: 8),
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _placeName,
                            builder: (_, value, _) => PressScale(
                              child: FilledButton.icon(
                                key: const ValueKey('record-mark'),
                                onPressed: value.text.trim().isEmpty
                                    ? null
                                    : _mark,
                                icon: const Icon(
                                  Icons.add_location_alt_rounded,
                                ),
                                label: const Text('Mark place'),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          children: [
                            if (_canUndo) ...[
                              Expanded(
                                child: PressScale(
                                  child: OutlinedButton(
                                    key: const ValueKey('record-undo'),
                                    onPressed: _undoMark,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                    ),
                                    child: const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text('Undo last'),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            if (_recording) ...[
                              Expanded(
                                child: PressScale(
                                  child: OutlinedButton(
                                    key: const ValueKey('record-finish-start'),
                                    onPressed: _saving ? null : _finishAtStart,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                    ),
                                    child: const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text('Finish at start'),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: PressScale(
                                child: FilledButton(
                                  key: const ValueKey('record-stop'),
                                  style: _secondaryFilled,
                                  onPressed: _saving || _savedPath != null
                                      ? null
                                      : _stop,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      _saving
                                          ? 'Saving map…'
                                          : _saveError != null
                                          ? 'Retry save'
                                          : 'Stop',
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
