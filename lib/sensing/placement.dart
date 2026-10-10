import 'dart:math' as math;

import '../core/tuning.dart' as tuning;
import 'raw_events.dart';
import 'state_events.dart';

/// UI-only placement. On-change values persist until changed or unavailable.
/// advanceTo supplies deterministic clock ticks without timers or Flutter.
class PlacementDetector {
  PlacementDetector({
    this.usePlacement = tuning.usePlacement,
    this.pocketLuxMax = tuning.pocketLuxMax,
    this.pocketHoldMs = tuning.pocketHoldMs,
  }) {
    if (!pocketLuxMax.isFinite || pocketLuxMax < 0 || pocketHoldMs < 0) {
      throw ArgumentError('Invalid pocket illuminance or dwell');
    }
  }
  final bool usePlacement;
  final double pocketLuxMax;
  final int pocketHoldMs;
  Placement _placement = Placement.unknown;
  Placement get placement => _placement;
  bool? _near;
  double? _lux;
  bool? _proximityAvailable, _lightAvailable;
  int? _lastProximityT, _lastLightT, _pocketSince;
  int _clock = -1;

  PlacementEvent? onProximity(ProximitySample sample) {
    if (!usePlacement ||
        sample.t < 0 ||
        !sample.cm.isFinite ||
        sample.cm < 0 ||
        (_lastProximityT != null && sample.t <= _lastProximityT!) ||
        _proximityAvailable == false) {
      return null;
    }
    _lastProximityT = sample.t;
    _near = sample.near;
    return _evaluate(math.max(_clock, sample.t));
  }

  PlacementEvent? onLight(LightSample sample) {
    if (!usePlacement ||
        sample.t < 0 ||
        !sample.lux.isFinite ||
        sample.lux < 0 ||
        (_lastLightT != null && sample.t <= _lastLightT!) ||
        _lightAvailable == false) {
      return null;
    }
    _lastLightT = sample.t;
    _lux = sample.lux;
    return _evaluate(math.max(_clock, sample.t));
  }

  PlacementEvent? onDeviceInfo(DeviceInfo info) {
    if (!usePlacement || (info.t != null && info.t! < 0)) return null;
    if (info.proximityAvailable != null) {
      _proximityAvailable = info.proximityAvailable;
      if (_proximityAvailable == false) {
        _near = null;
        _lastProximityT = null;
      }
    }
    if (info.lightAvailable != null) {
      _lightAvailable = info.lightAvailable;
      if (_lightAvailable == false) {
        _lux = null;
        _lastLightT = null;
      }
    }
    return _evaluate(math.max(math.max(_clock, 0), info.t ?? _clock));
  }

  PlacementEvent? advanceTo(int tMs) {
    if (!usePlacement || tMs < 0 || tMs < _clock) return null;
    return _evaluate(tMs);
  }

  PlacementEvent? _evaluate(int tMs) {
    _clock = tMs;
    final Placement next;
    if (_near == null || _lux == null) {
      _pocketSince = null;
      next = Placement.unknown;
    } else if (_near! && _lux! <= pocketLuxMax) {
      _pocketSince ??= tMs;
      next = tMs - _pocketSince! > pocketHoldMs
          ? Placement.pocket
          : Placement.hand;
    } else {
      _pocketSince = null;
      next = Placement.hand;
    }
    if (next == _placement) return null;
    _placement = next;
    return PlacementEvent(next, tMs);
  }
}
