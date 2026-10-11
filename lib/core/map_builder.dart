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

  /// D34: disabled recordings use the original coordinate-free map shape.
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

  /// Every mark that added a corridor, oldest first, for [undoLastMark].
  final _marks = <_Mark>[];

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
    _marks.clear();
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
    final key = name.trim().toLowerCase();
    for (final existing in _places) {
      if (existing.kind != contracts.PlaceKind.junction &&
          existing.name.trim().toLowerCase() == key) {
        // Already standing here: do not add a zero-step self corridor.
        if (existing.id == _from && _steps == 0) return;
        _marks.add(
          _Mark(
            existing.id,
            _corridors.length,
            created: false,
            beforeCorrection: useLoopCorrection ? List.of(_places) : null,
            closingPosition: useLoopCorrection ? _endPosition() : null,
          ),
        );
        if (useLoopCorrection) _correctLoop(existing);
        _closeAt(existing);
        _floor = existing.floor;
        return;
      }
    }
    _namedPlaces++;
    _marks.add(_Mark('p$_namedPlaces', _corridors.length, created: true));
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

  ({double x, double y}) _endPosition() =>
      _advance(_places.firstWhere((p) => p.id == _from), _steps, _heading);

  ({double x, double y}) _advance(
    contracts.Place from,
    int steps,
    double measuredHeading,
  ) {
    final nearest = contracts.normalizeHeading(
      (measuredHeading / tuning.turnSnapDegrees).roundToDouble() *
          tuning.turnSnapDegrees,
    );
    // Optional cardinal projection snap, never a change to stored headings.
    final heading =
        contracts.turnBetween(nearest, measuredHeading).abs() <=
            tuning.loopHeadingSnapToleranceDegrees
        ? nearest
        : measuredHeading;
    // Exact cardinal vectors make a zero-error square exactly zero, without
    // treating a nonzero closure error as zero via an arbitrary epsilon.
    switch (heading) {
      case 0:
        return (x: from.x!, y: from.y! + steps);
      case 90:
        return (x: from.x! - steps, y: from.y!);
      case 180:
        return (x: from.x!, y: from.y! - steps);
      case 270:
        return (x: from.x! + steps, y: from.y!);
      default:
        final rad = heading * math.pi / 180;
        return (
          x: from.x! - steps * math.sin(rad),
          y: from.y! + steps * math.cos(rad),
        );
    }
  }

  /// How many marks [undoLastMark] can still take back.
  int get undoableMarks => _active ? _marks.length : 0;

  /// Takes back the newest [addPlace] and returns its name, or null when there
  /// is nothing to undo. The walk stays: steps and turns are never removed.
  /// - Nothing closed since the mark: its corridor folds back into the open
  ///   one, as if the mark never happened.
  /// - The walk went on past it (a turn, a floor change or a later mark): a new
  ///   place becomes a junction; a loop join gets its own junction, so the
  ///   loop is no longer closed there.
  String? undoLastMark() {
    if (!_active || _marks.isEmpty) return null;
    final mark = _marks.removeLast();
    // D34: restore only display coordinates; keep main's mark/edge Undo rules.
    final oldPositions = mark.beforeCorrection;
    if (oldPositions != null) {
      final byId = {for (final p in oldPositions) p.id: p};
      for (var i = 0; i < _places.length; i++) {
        final p = _places[i];
        final old = byId[p.id];
        if (old != null) _places[i] = _positioned(p, old.x!, old.y!);
      }
    }
    final index = mark.corridor;
    final corridor = _corridors[index];
    final placeIndex = _places.indexWhere((p) => p.id == mark.placeId);
    final place = _places[placeIndex];
    if (index == _corridors.length - 1 && _from == place.id) {
      _corridors.removeLast();
      _travelled -= corridor.steps;
      _visits.removeLast();
      _distances.removeLast();
      _from = corridor.from;
      _steps += corridor.steps;
      _floor = _places.firstWhere((p) => p.id == corridor.from).floor;
      if (mark.created) {
        _places.removeAt(placeIndex);
        _namedPlaces--;
      }
    } else if (mark.created) {
      _junctions++;
      _places[placeIndex] = contracts.Place(
        id: place.id,
        name: 'Junction $_junctions',
        kind: contracts.PlaceKind.junction,
        floor: place.floor,
        x: place.x,
        y: place.y,
      );
    } else {
      final unpositioned = _junction(floor: place.floor);
      final end = mark.closingPosition;
      final junction = end == null
          ? unpositioned
          : _positioned(unpositioned, end.x, end.y);
      _places.add(junction);
      _visits[index + 1] = junction.id;
      _corridors[index] = _moved(corridor, to: junction.id);
      final next = index + 1;
      if (next < _corridors.length && _corridors[next].from == place.id) {
        _corridors[next] = _moved(_corridors[next], from: junction.id);
      } else if (_from == place.id) {
        _from = junction.id;
      }
    }
    // Any later turn/floor-change junction was projected from the corrected
    // join. Reproject that suffix from the detached visit, pinning older nodes.
    if (oldPositions != null && index < _corridors.length) {
      final pinned = oldPositions.map((p) => p.id).toSet();
      for (var i = index + 1; i < _corridors.length; i++) {
        final c = _corridors[i];
        if (pinned.contains(c.to)) continue;
        final from = _places.firstWhere((p) => p.id == c.from);
        final end = _advance(from, c.steps, c.heading);
        final to = _places.indexWhere((p) => p.id == c.to);
        _places[to] = _positioned(_places[to], end.x, end.y);
      }
    }
    return place.name;
  }

  static contracts.Corridor _moved(
    contracts.Corridor c, {
    String? from,
    String? to,
  }) => contracts.Corridor(
    id: c.id,
    from: from ?? c.from,
    to: to ?? c.to,
    steps: c.steps,
    heading: c.heading,
    kind: c.kind,
    floorDelta: c.floorDelta,
  );

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

  contracts.Place _junction({String? name, int? floor}) {
    _junctions++;
    return contracts.Place(
      id: 'j$_junctions',
      name: name ?? 'Junction $_junctions',
      kind: contracts.PlaceKind.junction,
      floor: floor ?? _floor,
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

/// One [MapBuilder.addPlace] that closed corridor number [corridor] at
/// [placeId]; [created] is false for a loop join to an existing place.
class _Mark {
  const _Mark(
    this.placeId,
    this.corridor, {
    required this.created,
    this.beforeCorrection,
    this.closingPosition,
  });
  final String placeId;
  final int corridor;
  final bool created;
  final List<contracts.Place>? beforeCorrection;
  final ({double x, double y})? closingPosition;
}
