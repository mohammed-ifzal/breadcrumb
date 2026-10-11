/// A recorded walk of connected places and junctions. No file or Flutter I/O.
library;

import 'contracts.dart' as contracts;
import 'tuning.dart' as tuning;

/// Builds one walk, snapping each turn before accumulating its heading.
///
/// Events/marks outside an active walk are ignored. [start] begins a fresh walk;
/// [finish] is idempotent. Queries before start throw [StateError]. Distinct turns
/// and places retain zero-step connections. Unmarked trailing steps end at a
/// permanent junction, never at the temporary [contracts.hereId].
class MapBuilder implements contracts.MapBuilder {
  final _places = <contracts.Place>[];
  final _corridors = <contracts.Corridor>[];
  String? _from;
  int _steps = 0;
  int _floor = 0;
  double _heading = 0;
  int _junctions = 0;
  int _namedPlaces = 0;
  contracts.MapGraph? _finished;

  /// Every mark that added a corridor, oldest first, for [undoLastMark].
  final _marks = <_Mark>[];

  bool get _active => _from != null && _finished == null;

  @override
  void start(String placeName) {
    _places.clear();
    _corridors.clear();
    _from = 'p0';
    _steps = 0;
    _floor = 0;
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
      ),
    );
  }

  @override
  void onStep(contracts.StepEvent e) {
    if (_active) _steps++;
  }

  @override
  void onTurn(contracts.TurnEvent e) {
    if (!_active || !e.angle.isFinite) return;
    _closeAt(_junction());
    // Dart's nearest rounding resolves exact halves away from zero for both
    // left and right turns. Snap each angle, not the accumulated heading.
    final angle =
        (e.angle / tuning.turnSnapDegrees).roundToDouble() *
        tuning.turnSnapDegrees;
    _heading = contracts.normalizeHeading(_heading + angle);
  }

  /// Completes a manual D24 transition, keeping prior walking on its old floor.
  /// The transition has zero steps: this tap reports arrival on another floor,
  /// rather than assigning preceding horizontal steps to stairs or a lift.
  /// This concrete capability does not change the shared MapBuilder interface.
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

  @override
  void addPlace(String name, List<String> aliases) {
    if (!_active) return;
    final key = name.trim().toLowerCase();
    for (final existing in _places) {
      if (existing.kind != contracts.PlaceKind.junction &&
          existing.name.trim().toLowerCase() == key) {
        // Already standing here: do not add a zero-step self corridor.
        if (existing.id == _from && _steps == 0) return;
        _marks.add(_Mark(existing.id, _corridors.length, created: false));
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
        aliases: List<String>.unmodifiable(aliases),
        kind: contracts.PlaceKind.place,
        floor: _floor,
      ),
    );
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
    final index = mark.corridor;
    final corridor = _corridors[index];
    final placeIndex = _places.indexWhere((p) => p.id == mark.placeId);
    final place = _places[placeIndex];
    if (index == _corridors.length - 1 && _from == place.id) {
      _corridors.removeLast();
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
      );
    } else {
      final junction = _junction(floor: place.floor);
      _places.add(junction);
      _corridors[index] = _moved(corridor, to: junction.id);
      final next = index + 1;
      if (next < _corridors.length && _corridors[next].from == place.id) {
        _corridors[next] = _moved(_corridors[next], from: junction.id);
      } else if (_from == place.id) {
        _from = junction.id;
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
    // Copies only: no IDs are allocated, no step count is consumed, and no
    // permanent node/corridor is added by drawing the temporary position.
    return _map(
      [
        ..._places,
        contracts.Place(
          id: contracts.hereId,
          name: 'You are here',
          kind: contracts.PlaceKind.junction,
          floor: _floor,
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
    if (!_places.any((existing) => existing.id == place.id)) _places.add(place);
    _from = place.id;
    _steps = 0;
  }

  contracts.MapGraph _map(
    List<contracts.Place> places,
    List<contracts.Corridor> corridors,
  ) => contracts.MapGraph(
    name: _places.first.name,
    start: _places.first.id,
    places: List<contracts.Place>.unmodifiable(places),
    corridors: List<contracts.Corridor>.unmodifiable(corridors),
  );
}

/// One [MapBuilder.addPlace] that closed corridor number [corridor] at
/// [placeId]; [created] is false for a loop join to an existing place.
class _Mark {
  const _Mark(this.placeId, this.corridor, {required this.created});
  final String placeId;
  final int corridor;
  final bool created;
}
