/// Optional raw sensor transport. These events never gate steps or turns.
library;

sealed class RawSensingEvent {
  const RawSensingEvent();
  int? get t;
  Map<String, Object?> toJson();

  factory RawSensingEvent.fromJson(Map<String, Object?> raw) =>
      switch (raw['type']) {
        'gravity' => GravitySample(
          _timestamp(raw['t']),
          _number(raw['x']),
          _number(raw['y']),
          _number(raw['z']),
          source: _source(raw['source']) ?? 'sensor',
        ),
        'proximity' => ProximitySample(
          _timestamp(raw['t']),
          _bool(raw['near']),
          _nonnegative(raw['cm']),
          maximumRange: raw['maximumRange'] == null
              ? null
              : _positive(raw['maximumRange']),
          origin: _proximityOrigin(raw['origin']),
          snapshot: _optionalBool(raw['snapshot']),
        ),
        'light' => LightSample(_timestamp(raw['t']), _nonnegative(raw['lux'])),
        'info' => DeviceInfo(
          t: raw['t'] == null ? null : _timestamp(raw['t']),
          totalRamMb: raw['totalRamMb'] == null
              ? null
              : _timestamp(raw['totalRamMb']),
          totalRamAvailable: _optionalBool(raw['totalRamAvailable']),
          gravityAvailable: _optionalBool(raw['gravityAvailable']),
          gravitySource: _source(raw['gravitySource']),
          gravityLowPassEnabled: _optionalBool(raw['gravityLowPassEnabled']),
          proximityAvailable: _optionalBool(raw['proximityAvailable']),
          lightAvailable: _optionalBool(raw['lightAvailable']),
          stepDetector: _optionalBool(raw['stepDetector']),
        ),
        _ => throw FormatException(
          'Unknown optional raw sensor event: ${raw['type']}',
        ),
      };
}

/// Gravity estimate in m/s², in Android device axes; not a normalized vector.
class GravitySample extends RawSensingEvent {
  const GravitySample(this.t, this.x, this.y, this.z, {this.source = 'sensor'});
  @override
  final int t;
  final double x, y, z;

  /// 'sensor' or 'accelerometer' (including the optional low-pass fallback).
  final String source;
  @override
  Map<String, Object?> toJson() => {
    'type': 'gravity',
    't': t,
    'x': x,
    'y': y,
    'z': z,
    'source': source,
  };
}

/// Native near/far relative to the sensor's own maximum range, plus raw cm.
class ProximitySample extends RawSensingEvent {
  const ProximitySample(
    this.t,
    this.near,
    this.cm, {
    this.maximumRange,
    this.origin,
    this.snapshot,
  });
  @override
  final int t;
  final bool near;
  final double cm;

  /// Sensor-defined far reference in cm; absent in older traces.
  final double? maximumRange;

  /// sensor = callback; cached = last known; assumed = fallback far reference.
  final String? origin;

  /// Current-state copy made when a trace starts, not a new hardware change.
  final bool? snapshot;
  @override
  Map<String, Object?> toJson() => {
    'type': 'proximity',
    't': t,
    'near': near,
    'cm': cm,
    if (maximumRange != null) 'maximumRange': maximumRange,
    if (origin != null) 'origin': origin,
    if (snapshot != null) 'snapshot': snapshot,
  };
}

/// Raw illuminance. Native transport sends changed values at no more than 5 Hz.
class LightSample extends RawSensingEvent {
  const LightSample(this.t, this.lux);
  @override
  final int t;
  final double lux;
  @override
  Map<String, Object?> toJson() => {'type': 'light', 't': t, 'lux': lux};
}

/// Partial capability notice. Null means not reported, never an inferred absence.
/// gravityAvailable describes the dedicated TYPE_GRAVITY sensor, not its fallback.
class DeviceInfo extends RawSensingEvent {
  const DeviceInfo({
    this.t,
    this.totalRamMb,
    this.totalRamAvailable,
    this.gravityAvailable,
    this.gravitySource,
    this.gravityLowPassEnabled,
    this.proximityAvailable,
    this.lightAvailable,
    this.stepDetector,
  });
  @override
  final int? t;

  /// ActivityManager's physical totalMem divided by 1024² (binary MB).
  final int? totalRamMb;
  final bool? totalRamAvailable,
      gravityAvailable,
      gravityLowPassEnabled,
      proximityAvailable,
      lightAvailable,
      stepDetector;
  final String? gravitySource;
  @override
  Map<String, Object?> toJson() => {
    'type': 'info',
    if (t != null) 't': t,
    if (totalRamMb != null) 'totalRamMb': totalRamMb,
    if (totalRamAvailable != null) 'totalRamAvailable': totalRamAvailable,
    if (gravityAvailable != null) 'gravityAvailable': gravityAvailable,
    if (gravitySource != null) 'gravitySource': gravitySource,
    if (gravityLowPassEnabled != null)
      'gravityLowPassEnabled': gravityLowPassEnabled,
    if (proximityAvailable != null) 'proximityAvailable': proximityAvailable,
    if (lightAvailable != null) 'lightAvailable': lightAvailable,
    if (stepDetector != null) 'stepDetector': stepDetector,
  };
}

double _positive(Object? value) {
  final number = _number(value);
  if (number <= 0) {
    throw const FormatException('Sensor maximum range must be positive');
  }
  return number;
}

String? _proximityOrigin(Object? value) {
  if (value == null) return null;
  if (!const {'sensor', 'cached', 'assumed'}.contains(value)) {
    throw const FormatException('Unknown proximity origin');
  }
  return value as String;
}

double _number(Object? value) {
  if (value is! num || !value.isFinite) {
    throw const FormatException('Expected a finite raw sensor number');
  }
  return value.toDouble();
}

double _nonnegative(Object? value) {
  final number = _number(value);
  if (number < 0) throw const FormatException('Negative raw sensor value');
  return number;
}

int _timestamp(Object? value) {
  final number = _nonnegative(value);
  if (number != number.truncateToDouble()) {
    throw const FormatException(
      'Expected a whole non-negative timestamp or RAM value',
    );
  }
  return number.toInt();
}

bool _bool(Object? value) {
  if (value is! bool) throw const FormatException('Expected a sensor boolean');
  return value;
}

bool? _optionalBool(Object? value) => value == null ? null : _bool(value);
String? _source(Object? value) {
  if (value == null) return null;
  if (value != 'sensor' && value != 'accelerometer') {
    throw const FormatException('Unknown gravity source');
  }
  return value as String;
}
