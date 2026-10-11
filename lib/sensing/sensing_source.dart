import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/contracts.dart' as contracts;
import '../core/tuning.dart' as tuning;
import 'raw_events.dart';
import 'step_detector.dart';
import 'trace_recorder.dart';
import 'turn_detector.dart';

/// One native subscription shared by all consumers and the optional raw recorder.
class SensingSource implements contracts.SensingSource {
  SensingSource({
    TraceRecorder? recorder,
    EventChannel channel = const EventChannel('breadcrumb/sensing'),
    bool gravityFallbackLowPassEnabled = tuning.gravityFallbackLowPassEnabled,
    double gravityFallbackLowPassAlpha = tuning.gravityFallbackLowPassAlpha,
    bool lightCoalescingEnabled = tuning.lightCoalescingEnabled,
    bool usePocketTurnProfile = tuning.usePocketTurnProfile,
    double pocketTurnRateMin = tuning.pocketTurnRateMin,
    int pocketTurnSettleMs = tuning.pocketTurnSettleMs,
  }) : _usePocketTurnProfile = usePocketTurnProfile,
       _pocketTurnRateMin = pocketTurnRateMin,
       _pocketTurnSettleMs = pocketTurnSettleMs,
       _turns = TurnDetector(
         usePocketTurnProfile: usePocketTurnProfile,
         pocketTurnRateMin: pocketTurnRateMin,
         pocketTurnSettleMs: pocketTurnSettleMs,
       ),
       _ownsRecorder = recorder == null,
       _recorder = recorder ?? TraceRecorder(),
       _filterConfig = {
         'gravityFallbackLowPassEnabled': gravityFallbackLowPassEnabled,
         'gravityFallbackLowPassAlpha': gravityFallbackLowPassAlpha,
         'lightCoalescingEnabled': lightCoalescingEnabled,
       },
       _raw = channel.receiveBroadcastStream({
         'gravityFallbackLowPassEnabled': gravityFallbackLowPassEnabled,
         'gravityFallbackLowPassAlpha': gravityFallbackLowPassAlpha,
         'lightCoalescingEnabled': lightCoalescingEnabled,
       }) {
    if (!gravityFallbackLowPassAlpha.isFinite ||
        gravityFallbackLowPassAlpha < 0 ||
        gravityFallbackLowPassAlpha >= 1) {
      throw ArgumentError.value(
        gravityFallbackLowPassAlpha,
        'gravityFallbackLowPassAlpha',
        'Must be finite and in [0, 1)',
      );
    }
    _recorder.state.addListener(_onTraceState);
    _events = StreamController<Object>.broadcast(
      onListen: _ensureListening,
      onCancel: _releaseIfIdle,
    );
  }

  final bool _usePocketTurnProfile;
  final double _pocketTurnRateMin;
  final int _pocketTurnSettleMs;
  final bool _ownsRecorder;
  final TraceRecorder _recorder;
  bool _startingTrace = false;
  final _pendingTrace = <Map<String, Object?>>[];
  final Stream<dynamic> _raw;
  final Map<String, Object?> _filterConfig;
  final _deviceInfo = <String, Object?>{};
  Map<String, Object?>? _proximityState;
  late final StreamController<Object> _events;
  StreamSubscription<dynamic>? _subscription;
  StepDetector _steps = StepDetector();
  TurnDetector _turns;
  Completer<void>? _capability;
  bool _tracing = false;
  bool _disposed = false;
  Future<void>? _disposing;
  int _lastT = 0;
  final Stopwatch _sinceSample = Stopwatch();

  /// Null until the first native notice/sample. A permission error stays unknown;
  /// it must never silently switch an existing hardware detector to fallback.
  final ValueNotifier<bool?> hardwareStepDetector = ValueNotifier(null);

  @override
  Stream<Object> events() {
    if (_disposed) throw StateError('Sensing source is disposed.');
    return _events.stream;
  }

  ValueListenable<TraceState> get traceState => _recorder.state;

  void _onTraceState() {
    if (_recorder.state.value.error != null) {
      _tracing = false;
      unawaited(_releaseIfIdle());
    }
  }

  void _ensureListening() {
    if (_disposed) throw StateError('Sensing source is disposed.');
    if (_subscription != null) return;
    _steps = StepDetector();
    _turns = TurnDetector(
      usePocketTurnProfile: _usePocketTurnProfile,
      pocketTurnRateMin: _pocketTurnRateMin,
      pocketTurnSettleMs: _pocketTurnSettleMs,
    );
    _lastT = 0;
    _sinceSample.reset();
    hardwareStepDetector.value = null;
    _deviceInfo.clear();
    _proximityState = null;
    _capability = Completer<void>();
    // Observe errors even when nobody is currently waiting for startTrace.
    unawaited(
      _capability!.future.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      ),
    );
    _subscription = _raw.listen(
      _onRaw,
      onError: _onError,
      onDone: () {
        _onError(
          StateError('Native sensing stream ended.'),
          StackTrace.current,
        );
      },
    );
  }

  void _onError(Object error, StackTrace stack) {
    if (_disposed) return;
    if (_capability != null && !_capability!.isCompleted) {
      _capability!.completeError(error, stack);
    }
    _events.addError(error, stack);
  }

  void _onRaw(dynamic value) {
    var optionalPacket = false;
    try {
      final raw = Map<String, Object?>.from(value as Map);
      _writeTrace(raw);
      final type = raw['type'];
      optionalPacket =
          type == 'gravity' ||
          type == 'proximity' ||
          type == 'light' ||
          (type == 'info' &&
              raw.keys.any(
                (key) => const {
                  'totalRamMb',
                  'totalRamAvailable',
                  'gravityAvailable',
                  'gravitySource',
                  'gravityLowPassEnabled',
                  'proximityAvailable',
                  'lightAvailable',
                }.contains(key),
              ));
      if (type == 'gravity' || type == 'proximity' || type == 'light') {
        final event = RawSensingEvent.fromJson(raw);
        _turns.onRaw(event);
        if (event is ProximitySample) _proximityState = Map.of(raw);
        _observeTimestamp(event.t!);
        _events.add(event);
      } else if (type == 'info') {
        // Step-only notices keep their original API behavior. Auxiliary notices
        // are typed, cached for future trace starts, and never imply hardware steps.
        if (raw.keys.any(
          (key) => const {
            'totalRamMb',
            'totalRamAvailable',
            'gravityAvailable',
            'gravitySource',
            'gravityLowPassEnabled',
            'proximityAvailable',
            'lightAvailable',
          }.contains(key),
        )) {
          final event = RawSensingEvent.fromJson(raw) as DeviceInfo;
          _turns.onRaw(event);
          _deviceInfo.addAll(event.toJson());
          if (event.proximityAvailable == false) _proximityState = null;
          _events.add(event);
        }
        if (raw['stepDetector'] == false) {
          if (hardwareStepDetector.value != false) _steps = StepDetector();
          hardwareStepDetector.value = false;
        }
      } else if (type == 'motion' || type == 'step') {
        final t = (raw['t'] as num).toInt();
        if (t < 0) throw const FormatException('Negative sensing timestamp.');
        _observeTimestamp(t);
        // Kotlin sends its absence notice before any samples. Without that notice,
        // the first valid sample confirms that the hardware detector exists.
        hardwareStepDetector.value ??= true;
        if (type == 'step') {
          if (hardwareStepDetector.value == true) {
            _events.add(contracts.StepEvent(t));
          }
        } else {
          final accel = (raw['accel'] as num).toDouble();
          final yawRate = (raw['yawRate'] as num).toDouble();
          if (hardwareStepDetector.value == false) {
            final step = _steps.onMotion(t, accel);
            if (step != null) _events.add(step);
          }
          final turn = _turns.onMotion(t, yawRate);
          if (turn != null) _events.add(turn);
        }
      } else {
        throw FormatException('Unknown sensing event: $type');
      }
      if (hardwareStepDetector.value != null && !_capability!.isCompleted) {
        _capability!.complete();
      }
    } catch (error, stack) {
      // Optional packet decoding must not poison motion capability/startTrace.
      if (optionalPacket) {
        _events.addError(error, stack);
      } else {
        _onError(error, stack);
      }
    }
  }

  void _observeTimestamp(int t) {
    if (t >= _lastT) {
      _lastT = t;
      _sinceSample
        ..reset()
        ..start();
    }
  }

  Future<void> _releaseIfIdle() async {
    if (_tracing || _events.hasListener) return;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    _sinceSample.stop();
  }

  @override
  Future<void> startTrace(Map<String, Object?> meta) async {
    if (_tracing) throw StateError('A trace is already active.');
    _tracing = true;
    _startingTrace = true;
    _pendingTrace.clear();
    try {
      _ensureListening();
      await _capability!.future;
      if (_disposed) throw StateError('Sensing source is disposed.');
      await _recorder.start({
        ...meta,
        'rawSensorFilters': Map<String, Object?>.of(_filterConfig),
        'stepSource': hardwareStepDetector.value == false
            ? 'accel'
            : 'hardware',
      });
      // The native RAM/capability notices usually precede Start trace. Preserve
      // their latest fields after meta without inventing events in old traces.
      if (_deviceInfo.isNotEmpty) _recorder.record(Map.of(_deviceInfo));
      final proximity = _proximityState;
      if (proximity != null) {
        // Preserve the current known state even when its on-change callback
        // preceded Start trace. Timestamp this copy at capture, not stream start.
        _recorder.record({
          ...proximity,
          't': _lastT + _sinceSample.elapsedMilliseconds,
          'origin': proximity['origin'] == 'assumed' ? 'assumed' : 'cached',
          'snapshot': true,
        });
      }
      final pending = List<Map<String, Object?>>.of(_pendingTrace);
      _pendingTrace.clear();
      _startingTrace = false;
      for (final row in pending) {
        _recorder.record(row);
      }
      if (!_recorder.state.value.recording) {
        _tracing = false;
        await _releaseIfIdle();
      }
    } catch (_) {
      _startingTrace = false;
      _pendingTrace.clear();
      _tracing = false;
      await _releaseIfIdle();
      rethrow;
    }
  }

  @override
  Future<void> stopTrace() async {
    try {
      await _recorder.stop();
    } finally {
      _tracing = false;
      await _releaseIfIdle();
    }
  }

  void _writeTrace(Map<String, Object?> row) {
    if (_startingTrace) {
      _pendingTrace.add(Map.of(row));
    } else if (_tracing) {
      _recorder.record(row);
    }
  }

  @override
  void mark(String note) => _writeTrace({
    'type': 'mark',
    't': _lastT + _sinceSample.elapsedMilliseconds,
    'note': note,
  });

  // D29 compile stubs added by the captain with the contract change; Teammate 2
  // replaces them with real motion state, placement and RAM readings.
  @override
  Stream<contracts.MotionStateEvent> motionStates() => const Stream.empty();

  @override
  Stream<contracts.PlacementEvent> placements() => const Stream.empty();

  @override
  Future<int> totalRamMb() async => 0;

  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_capability != null && !_capability!.isCompleted) {
      _capability!.completeError(StateError('Sensing source is disposed.'));
    }
    await _subscription?.cancel();
    _subscription = null;
    _recorder.state.removeListener(_onTraceState);
    if (_ownsRecorder) {
      await _recorder.dispose();
    } else {
      await _recorder.stop();
    }
    await _events.close();
    _sinceSample.stop();
    hardwareStepDetector.dispose();
  }
}
