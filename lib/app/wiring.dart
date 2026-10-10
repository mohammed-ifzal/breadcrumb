import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:breadcrumb/ai/destination_resolver.dart';
import 'package:breadcrumb/ai/gemma_service.dart';
import 'package:breadcrumb/ai/speech_input.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/fakes.dart';
import 'package:breadcrumb/core/map_json.dart';
import 'package:breadcrumb/core/route_planner.dart';
import 'package:breadcrumb/core/place_matcher.dart';
import 'package:breadcrumb/core/tracker.dart';
import 'package:breadcrumb/core/guide.dart';
import 'package:breadcrumb/sensing/sensing_source.dart' as real_sensing;
import 'package:breadcrumb/app/speaker.dart';

class Wiring {
  static Wiring instance = Wiring._();

  Wiring._() {
    _activeMap = defaultDemoMap;
    tracker = RouteTracker(_activeMap);
    guide = RouteGuide(_activeMap);
    tracker.setRoute(planner.plan(_activeMap, _activeMap.start, _activeMap.start));
    sensorEvents = _createSensorEventsStream;
  }

  static const MapGraph defaultDemoMap = MapGraph(
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

  MapGraph _activeMap = defaultDemoMap;
  MapGraph get map => _activeMap;

  set map(MapGraph newMap) {
    _activeMap = newMap;
    tracker = RouteTracker(_activeMap);
    guide = RouteGuide(_activeMap);
    currentPlaceId = defaultStartPlaceId(_activeMap);
  }

  /// D23: Navigate defaults "You are at" to the map's last place
  /// (the last node with kind: place in walk order).
  static String defaultStartPlaceId(MapGraph map) {
    final places = map.places;
    for (int i = places.length - 1; i >= 0; i--) {
      if (places[i].kind == PlaceKind.place) {
        return places[i].id;
      }
    }
    return map.start;
  }

  String? currentPlaceId;
  String get effectiveCurrentPlaceId => currentPlaceId ?? defaultStartPlaceId(map);

  final RoutePlanner planner = DijkstraRoutePlanner();
  final PlaceMatcher matcher = FuzzyPlaceMatcher();
  late Tracker tracker;
  late Guide guide;
  final StepDetector stepDetector = FakeStepDetector();
  final TurnDetector turnDetector = FakeTurnDetector();
  final MapBuilder mapBuilder = FakeMapBuilder();

  /// Real SensingSource wrapping native EventChannel breadcrumb/sensing
  SensingSource sensingSource = real_sensing.SensingSource();
  final SignReader signReader = FakeSignReader();

  final GemmaService gemmaService = GemmaService();
  final ValueNotifier<bool> isAiReady = ValueNotifier<bool>(false);
  final SpeechInput speechInput = SpeechInput();

  late DestinationResolver destinationResolver = GemmaDestinationResolver(
    matcher: FuzzyPlaceMatcher(),
    chooser: gemmaService,
  );
  Speaker speaker = AppSpeaker();

  final StreamController<Object> _simulatedEventsController = StreamController<Object>.broadcast();

  /// Event source for step and turn events. Listens to real sensing source
  /// while also admitting simulated events for testing.
  late Stream<Object> Function() sensorEvents;

  Stream<Object> _createSensorEventsStream() {
    final controller = StreamController<Object>.broadcast();
    StreamSubscription<Object>? subReal;
    StreamSubscription<Object>? subSim;

    controller.onListen = () {
      try {
        subReal = sensingSource.events().listen(
          controller.add,
          onError: (Object error, StackTrace stack) {
            // In widget tests without native mock, ignore missing plugin errors
          },
        );
      } catch (_) {}
      subSim = _simulatedEventsController.stream.listen(controller.add);
    };

    controller.onCancel = () {
      subReal?.cancel();
      subSim?.cancel();
    };

    return controller.stream;
  }

  void emitSimulatedEvent(Object event) {
    if (!_simulatedEventsController.isClosed) {
      _simulatedEventsController.add(event);
    }
  }

  /// D22: Load maps/latest.json from app documents directory if present,
  /// otherwise keep default demo map.
  Future<bool> reloadActiveMap({Directory? documentsDir}) async {
    try {
      final dir = documentsDir ?? await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/maps/latest.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final loaded = decodeMap(content);
        map = loaded;
        return true;
      }
    } catch (e) {
      // Graceful fallback to current map if file cannot be read
    }
    return false;
  }

  /// Warm up Gemma LLM in the background and update [isAiReady].
  Future<bool> warmAi() async {
    try {
      if (!gemmaService.isLoaded) {
        await gemmaService.load();
      }
      isAiReady.value = true;
      return true;
    } catch (_) {
      isAiReady.value = false;
      return false;
    }
  }
}
