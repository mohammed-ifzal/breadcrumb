import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/contracts.dart' as contracts;
import 'step_detector.dart';
import 'trace_recorder.dart';
import 'turn_detector.dart';

/// One native subscription shared by all consumers and the optional raw recorder.
class SensingSource implements contracts.SensingSource {
  SensingSource({
    TraceRecorder? recorder,
    EventChannel channel = const EventChannel('breadcrumb/sensing'),
  }) : _recorder = recorder ?? TraceRecorder(),
       _raw = channel.receiveBroadcastStream() {
    _recorder.state.addListener(_onTraceState);
    _events = StreamController<Object>.broadcast(
      onListen: _ensureListening,
      onCancel: _releaseIfIdle,
    );
  }

  final TraceRecorder _recorder;
  final Stream<dynamic> _raw;
  late final StreamController<Object> _events;
  StreamSubscription<dynamic>? _subscription;
  StepDetector _steps = StepDetector();
  TurnDetector _turns = TurnDetector();
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
    _turns = TurnDetector();
    _lastT = 0;
    _sinceSample.reset();
    hardwareStepDetector.value = null;
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
    try {
      final raw = Map<String, Object?>.from(value as Map);
      _recorder.record(raw);
      final type = raw['type'];
      if (type == 'info') {
        if (raw['stepDetector'] == false) {
          if (hardwareStepDetector.value != false) _steps = StepDetector();
          hardwareStepDetector.value = false;
        }
      } else if (type == 'motion' || type == 'step') {
        final t = (raw['t'] as num).toInt();
        if (t < 0) throw const FormatException('Negative sensing timestamp.');
        if (t >= _lastT) {
          _lastT = t;
          _sinceSample
            ..reset()
            ..start();
        }
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
      _onError(error, stack);
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
    try {
      _ensureListening();
      await _capability!.future;
      if (_disposed) throw StateError('Sensing source is disposed.');
      await _recorder.start({
        ...meta,
        'stepSource': hardwareStepDetector.value == false
            ? 'accel'
            : 'detector',
      });
      if (!_recorder.state.value.recording) {
        _tracing = false;
        await _releaseIfIdle();
      }
    } catch (_) {
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

  @override
  void mark(String note) =>
      _recorder.mark(_lastT + _sinceSample.elapsedMilliseconds, note);

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
    await _recorder.dispose();
    await _events.close();
    _sinceSample.stop();
    hardwareStepDetector.dispose();
  }
}
