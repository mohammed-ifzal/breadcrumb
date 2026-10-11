/// A recorded walk of connected places and junctions. No file or Flutter I/O.
library;

import 'dart:math' as math;

import 'contracts.dart' as contracts;
import 'tuning.dart' as tuning;

/// Read-only geometry check; the screen decides whether to confirm a large join.
class LoopClosurePreview {
  const LoopClosurePreview({
    required this.placeName,
    required this.errorSteps,
    required this.loopSteps,
  });
  final String placeName;
  final double errorSteps;
  final int loopSteps;
  bool get requiresConfirmation =>
      loopSteps > 0 &&
      errorSteps > loopSteps * tuning.loopClosureMaxErrorFraction;
}

/// Builds one walk. Coordinates are display-only; measured corridor steps and
/// headings remain unchanged. Loop correction pins every node visited before
/// the target's latest occurrence, including the target itself.
class MapBuilder implements contracts.MapBuilder {
  MapBuilder({this.useLoopCorrection = tuning.useLoopCorrection});

  /// D33: disabled recordings use the original coordinate-free map shape.
  final bool useLoopCorrection;
  final _places = <contracts.Place>[];
  final _corridors = <contracts.Corridor>[];
  final _visits = <String>[];
  final _distances = <int>[];
  String? _from;
  int _steps = 0, _floor = 0, _travelled = 0;
  double _heading = 0;
  int _junctions = 0, _namedPlaces = 0;
  contracts.MapGraph? _finished;
  bool get _active => _from != null && _finished == null;

  @override
  void start(String placeName) {
    _places.clear();
    _corridors.clear();
    _visits.clear();
    _distances.clear();
    _from = 'p0';
    _steps = 0;
    _floor = 0;
    _travelled = 0;
    _heading = 0;
    _junctions = 0;
    _namedPlaces = 0;
    _finished = null;
    _places.add(
      contracts.Place(
        id: 'p0',
        name: placeName,
        kind: contracts.PlaceKind.start,
        x: useLoopCorrection ? 0 : null,
        y: useLoopCorrection ? 0 : null,
      ),
    );
    _visits.add('p0');
    _distances.add(0);
  }

  @override
  void onStep(contracts.StepEvent e) {
    if (_active) _steps++;
  }

  @override
  void onTurn(contracts.TurnEvent e) {
    if (!_active || !e.angle.isFinite) return;
    _closeAt(_junction());
    final angle =
        (e.angle / tuning.turnSnapDegrees).roundToDouble() *
        tuning.turnSnapDegrees;
    _heading = contracts.normalizeHeading(_heading + angle);
  }

  void changeFloor(int delta, contracts.CorridorKind kind) {
    if (!_active) return;
    if (delta == 0 || kind == contracts.CorridorKind.walk) {
      throw ArgumentError(
        'A floor change needs a nonzero delta and transition kind',
      );
    }
    if (_steps > 0) _closeAt(_junction());
    _floor += delta;
    _closeAt(_junction(), kind: kind, floorDelta: delta);
  }

  contracts.Place? _existing(String name) {
    final key = name.trim().toLowerCase();
    for (final p in _places) {
      if (p.kind != contracts.PlaceKind.junction &&
          p.name.trim().toLowerCase() == key) {
        return p;
      }
    }
    return null;
  }

  LoopClosurePreview? previewLoopClosure(String name) {
    if (!useLoopCorrection || !_active) return null;
    final target = _existing(name);
    if (target == null) return null;
    final start = _visits.lastIndexOf(target.id);
    final end = _endPosition();
    return LoopClosurePreview(
      placeName: target.name,
      errorSteps: math.sqrt(
        math.pow(target.x! - end.x, 2) + math.pow(target.y! - end.y, 2),
      ),
      loopSteps: _travelled - _distances[start] + _steps,
    );
  }

  @override
  void addPlace(String name, List<String> aliases) {
    if (!_active) return;
    final existing = _existing(name);
    if (existing != null) {
      if (existing.id == _from && _steps == 0) return;
      if (useLoopCorrection) _correctLoop(existing);
      _closeAt(existing);
      _floor = existing.floor;
      return;
    }
    _namedPlaces++;
    _closeAt(
      contracts.Place(
        id: 'p$_namedPlaces',
        name: name.trim(),
        aliases: List.unmodifiable(aliases),
        kind: contracts.PlaceKind.place,
        floor: _floor,
      ),
    );
  }

  /// The loop segment is the recorded visit interval after the latest target
  /// visit through the new closing point. Older node IDs are pinned even if
  /// revisited inside that interval. Repeated new IDs use their latest fraction.
  void _correctLoop(contracts.Place target) {
    final start = _visits.lastIndexOf(target.id);
    final length = _travelled - _distances[start] + _steps;
    final end = _endPosition();
    final dx = target.x! - end.x, dy = target.y! - end.y;
    if (length == 0 || (dx == 0 && dy == 0)) return;
    final pinned = _visits.take(start + 1).toSet();
    final original = {for (final p in _places) p.id: p};
    final corrected = <String, contracts.Place>{};
    for (var i = start + 1; i < _visits.length; i++) {
      final id = _visits[i];
      if (pinned.contains(id)) continue;
      final p = original[id]!;
      final fraction = (_distances[i] - _distances[start]) / length;
      corrected[id] = _positioned(
        p,
        p.x! + fraction * dx,
        p.y! + fraction * dy,
      );
    }
    for (var i = 0; i < _places.length; i++) {
      _places[i] = corrected[_places[i].id] ?? _places[i];
    }
  }

  ({double x, double y}) _endPosition() {
    final from = _places.firstWhere((p) => p.id == _from);
    final nearest = contracts.normalizeHeading(
      (_heading / tuning.turnSnapDegrees).roundToDouble() *
          tuning.turnSnapDegrees,
    );
    // Optional cardinal projection snap, never a change to stored headings.
    final heading =
        contracts.turnBetween(nearest, _heading).abs() <=
            tuning.loopHeadingSnapToleranceDegrees
        ? nearest
        : _heading;
    // Exact cardinal vectors make a zero-error square exactly zero, without
    // treating a nonzero closure error as zero via an arbitrary epsilon.
    switch (heading) {
      case 0:
        return (x: from.x!, y: from.y! + _steps);
      case 90:
        return (x: from.x! - _steps, y: from.y!);
      case 180:
        return (x: from.x!, y: from.y! - _steps);
      case 270:
        return (x: from.x! + _steps, y: from.y!);
      default:
        final rad = heading * math.pi / 180;
        return (
          x: from.x! - _steps * math.sin(rad),
          y: from.y! + _steps * math.cos(rad),
        );
    }
  }

  @override
  contracts.MapGraph snapshot() {
    final finished = _finished;
    if (finished != null) return finished;
    final from = _from;
    if (from == null) throw StateError('snapshot() before start()');
    final end = useLoopCorrection ? _endPosition() : null;
    return _map(
      [
        ..._places,
        contracts.Place(
          id: contracts.hereId,
          name: 'You are here',
          kind: contracts.PlaceKind.junction,
          floor: _floor,
          x: end?.x,
          y: end?.y,
        ),
      ],
      [
        ..._corridors,
        contracts.Corridor(
          id: 'c${_corridors.length + 1}',
          from: from,
          to: contracts.hereId,
          steps: _steps,
          heading: _heading,
        ),
      ],
    );
  }

  @override
  contracts.MapGraph finish() {
    final finished = _finished;
    if (finished != null) return finished;
    if (_from == null) throw StateError('finish() before start()');
    if (_steps > 0) _closeAt(_junction(name: 'End of trail'));
    return _finished = _map(_places, _corridors);
  }

  contracts.Place _junction({String? name}) {
    _junctions++;
    return contracts.Place(
      id: 'j$_junctions',
      name: name ?? 'Junction $_junctions',
      kind: contracts.PlaceKind.junction,
      floor: _floor,
    );
  }

  void _closeAt(
    contracts.Place place, {
    contracts.CorridorKind kind = contracts.CorridorKind.walk,
    int floorDelta = 0,
  }) {
    final end = useLoopCorrection ? _endPosition() : null;
    _corridors.add(
      contracts.Corridor(
        id: 'c${_corridors.length + 1}',
        from: _from!,
        to: place.id,
        steps: _steps,
        heading: _heading,
        kind: kind,
        floorDelta: floorDelta,
      ),
    );
    if (!_places.any((p) => p.id == place.id)) {
      _places.add(end == null ? place : _positioned(place, end.x, end.y));
    }
    _travelled += _steps;
    _visits.add(place.id);
    _distances.add(_travelled);
    _from = place.id;
    _steps = 0;
  }

  contracts.Place _positioned(contracts.Place p, double x, double y) =>
      contracts.Place(
        id: p.id,
        name: p.name,
        aliases: p.aliases,
        kind: p.kind,
        floor: p.floor,
        x: x,
        y: y,
      );

  contracts.MapGraph _map(
    List<contracts.Place> places,
    List<contracts.Corridor> corridors,
  ) => contracts.MapGraph(
    name: _places.first.name,
    start: _places.first.id,
    places: List.unmodifiable(places),
    corridors: List.unmodifiable(corridors),
  );
}
