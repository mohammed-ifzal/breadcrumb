import 'dart:async';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/fakes.dart';
import 'package:breadcrumb/core/route_planner.dart';
import 'package:breadcrumb/core/place_matcher.dart';
import 'package:breadcrumb/core/tracker.dart';
import 'package:breadcrumb/core/guide.dart';
import 'package:breadcrumb/app/speaker.dart';

class Wiring {
  static final Wiring instance = Wiring._();
  
  Wiring._() {
    tracker.setRoute(planner.plan(map, map.start, map.start));
  }

  final MapGraph map = const MapGraph(
    name: 'Demo Map',
    start: 'entrance',
    places: [
      Place(id: 'entrance', name: 'Entrance', kind: PlaceKind.start),
      Place(id: 'j1', name: 'Junction 1', kind: PlaceKind.junction),
      Place(id: 'cafe', name: 'Cafe', aliases: ['coffee', 'food'], kind: PlaceKind.place),
      Place(id: 'j2', name: 'Junction 2', kind: PlaceKind.junction),
      Place(id: 'stage', name: 'Stage Side', kind: PlaceKind.place),
      Place(id: 'restroom', name: 'Restroom', kind: PlaceKind.place),
    ],
    corridors: [
      Corridor(id: 'c1', from: 'entrance', to: 'j1', steps: 15, heading: 0),
      Corridor(id: 'c2', from: 'j1', to: 'cafe', steps: 10, heading: 90),
      Corridor(id: 'c3', from: 'j1', to: 'j2', steps: 20, heading: 0),
      Corridor(id: 'c4', from: 'j2', to: 'stage', steps: 12, heading: 270),
      Corridor(id: 'c5', from: 'j2', to: 'restroom', steps: 8, heading: 0),
    ],
  );

  String? currentPlaceId;
  String get effectiveCurrentPlaceId => currentPlaceId ?? map.start;

  final RoutePlanner planner = DijkstraRoutePlanner();
  final PlaceMatcher matcher = FuzzyPlaceMatcher();
  late final Tracker tracker = RouteTracker(map);
  late final Guide guide = RouteGuide(map);
  final StepDetector stepDetector = FakeStepDetector();
  final TurnDetector turnDetector = FakeTurnDetector();
  final MapBuilder mapBuilder = FakeMapBuilder();
  final SensingSource sensingSource = FakeSensingSource();
  final SignReader signReader = FakeSignReader();
  final DestinationResolver destinationResolver = FakeDestinationResolver();
  final Speaker speaker = AppSpeaker();

  final StreamController<Object> _simulatedEventsController = StreamController<Object>.broadcast();

  /// Event source for step and turn events, matching the exact signature
  /// of SensingSource.events(). When PR #2 lands on main, swap this one line to:
  /// `late final Stream<Object> Function() sensorEvents = sensingSource.events;`
  late final Stream<Object> Function() sensorEvents = () => _simulatedEventsController.stream;

  void emitSimulatedEvent(Object event) {
    if (!_simulatedEventsController.isClosed) {
      _simulatedEventsController.add(event);
    }
  }
}
