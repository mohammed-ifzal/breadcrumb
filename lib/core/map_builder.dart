/// A recorded walk as a chain of places and junctions. No file or Flutter I/O.
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
  double _heading = 0;
  int _junctions = 0;
  int _namedPlaces = 0;
  contracts.MapGraph? _finished;

  bool get _active => _from != null && _finished == null;

  @override
  void start(String placeName) {
    _places.clear();
    _corridors.clear();
    _from = 'p0';
    _steps = 0;
    _heading = 0;
    _junctions = 0;
    _namedPlaces = 0;
    _finished = null;
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

  @override
  void addPlace(String name, List<String> aliases) {
    if (!_active) return;
    _namedPlaces++;
    _closeAt(
      contracts.Place(
        id: 'p$_namedPlaces',
        name: name,
        aliases: List<String>.unmodifiable(aliases),
        kind: contracts.PlaceKind.place,
      ),
    );
  }

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
        const contracts.Place(
          id: contracts.hereId,
          name: 'You are here',
          kind: contracts.PlaceKind.junction,
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
    );
  }

  void _closeAt(contracts.Place place) {
    _corridors.add(
      contracts.Corridor(
        id: 'c${_corridors.length + 1}',
        from: _from!,
        to: place.id,
        steps: _steps,
        heading: _heading,
      ),
    );
    _places.add(place);
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
