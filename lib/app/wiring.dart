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
import 'package:breadcrumb/core/turn_confirmer.dart';
import 'package:breadcrumb/core/tuning.dart' as tuning;
import 'package:breadcrumb/sensing/sensing_source.dart' as real_sensing;
import 'package:breadcrumb/app/speaker.dart';
import 'package:breadcrumb/perception/mlkit_sign_reader.dart';

enum AiState { loading, ready, unavailable }

class AiStatus {
  const AiStatus.loading()
      : state = AiState.loading,
        reason = null;
  const AiStatus.ready()
      : state = AiState.ready,
        reason = null;
  const AiStatus.unavailable([this.reason = 'model not loaded'])
      : state = AiState.unavailable;

  final AiState state;
  final String? reason;

  bool get isLoading => state == AiState.loading;
  bool get isReady => state == AiState.ready;
  bool get isUnavailable => state == AiState.unavailable;

  @override
  String toString() => 'AiStatus($state, reason: $reason)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiStatus && other.state == state && other.reason == reason;

  @override
  int get hashCode => Object.hash(state, reason);
}

class Wiring {
  static Wiring instance = Wiring._();

  Wiring._() {
    _activeMap = defaultDemoMap;
    tracker = RouteTracker(_activeMap);
    guide = RouteGuide(_activeMap);
    tracker.setRoute(planner.plan(_activeMap, _activeMap.start, _activeMap.start));
    sensorEvents = _createSensorEventsStream;

    isAiReady.addListener(() {
      if (isAiReady.value) {
        _warmAiTimer?.cancel();
        _warmAiTimer = null;
        if (!aiStatus.value.isReady) {
          aiStatus.value = const AiStatus.ready();
        }
      } else if (aiStatus.value.isReady) {
        aiStatus.value = const AiStatus.loading();
      }
    });

    aiStatus.addListener(() {
      if (aiStatus.value.isReady && !isAiReady.value) {
        isAiReady.value = true;
      } else if (!aiStatus.value.isReady && isAiReady.value) {
        isAiReady.value = false;
      }
    });
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

  /// Whether [map] represents the bundled demo map.
  bool get isDemoMap =>
      map.name == defaultDemoMap.name ||
      map.name.toLowerCase().contains('demo');

  set map(MapGraph newMap) {
    _activeMap = newMap;
    _loadedMapJson = null;
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
  SignReader signReader = MlKitSignReader();

  final GemmaService gemmaService = GemmaService();
  final ValueNotifier<AiStatus> aiStatus =
      ValueNotifier<AiStatus>(const AiStatus.loading());
  final ValueNotifier<bool> isAiReady = ValueNotifier<bool>(false);
  SpeechInput speechInput = SpeechInput();
  PlaceMatcher placeMatcher = FuzzyPlaceMatcher();

  Duration aiWarmTimeout = const Duration(seconds: 90);
  Duration destinationResolveTimeout = const Duration(seconds: 20);
  Future<void> Function()? gemmaLoader;
  Future<bool>? _warmAiInFlight;
  Timer? _warmAiTimer;

  late DestinationResolver destinationResolver = GemmaDestinationResolver(
    matcher: FuzzyPlaceMatcher(),
    chooser: gemmaService,
  );
  Speaker speaker = AppSpeaker();

  final StreamController<Object> _simulatedEventsController = StreamController<Object>.broadcast();

  /// Event source for step and turn events. Listens to real sensing source
  /// while also admitting simulated events for testing.
  late Stream<Object> Function() sensorEvents;

  /// D29: with `useTurnConfirmer`, real sensor turns pass only once walking
  /// confirms them (simulated events are not filtered).
  bool useTurnConfirmer = tuning.useTurnConfirmer;

  Stream<Object> _createSensorEventsStream() {
    final controller = StreamController<Object>.broadcast();
    StreamSubscription<Object>? subReal;
    StreamSubscription<Object>? subSim;

    controller.onListen = () {
      try {
        final real = useTurnConfirmer
            ? confirmedEvents(sensingSource)
            : sensingSource.events();
        subReal = real.listen(
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

  /// Where [reloadActiveMap] looks for maps/latest.json; tests point it at a
  /// temporary directory.
  Future<Directory> Function() documentsDirectory = getApplicationDocumentsDirectory;

  /// The latest.json content behind [map], so an unchanged file is not reloaded
  /// (which would reset the "You are at" choice).
  String? _loadedMapJson;

  /// D22: Load maps/latest.json from app documents directory if present,
  /// otherwise keep default demo map. Called whenever Navigate opens, so a map
  /// saved after app start is used without a restart.
  Future<bool> reloadActiveMap({Directory? documentsDir}) async {
    try {
      final dir = documentsDir ?? await documentsDirectory();
      final file = File('${dir.path}/maps/latest.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content == _loadedMapJson) return true;
        final loaded = decodeMap(content);
        map = loaded;
        _loadedMapJson = content;
        return true;
      }
    } catch (e) {
      // Graceful fallback to current map if file cannot be read
    }
    return false;
  }

  /// Warm up Gemma LLM in the background and update [aiStatus] / [isAiReady].
  ///
  /// Catches errors and timeouts to transition to unavailable ("model not loaded").
  /// Concurrent calls share one in-flight Future.
  Future<bool> warmAi({Duration? timeout}) {
    if (aiStatus.value.isReady) return Future.value(true);
    if (_warmAiInFlight != null) return _warmAiInFlight!;

    final effectiveTimeout = timeout ?? aiWarmTimeout;
    final future = _performWarmAi(effectiveTimeout);
    _warmAiInFlight = future;
    return future.whenComplete(() {
      _warmAiInFlight = null;
    });
  }

  Future<bool> _performWarmAi(Duration timeout) async {
    aiStatus.value = const AiStatus.loading();
    isAiReady.value = false;

    final timeoutCompleter = Completer<void>();
    _warmAiTimer?.cancel();
    _warmAiTimer = Timer(timeout, () {
      if (!timeoutCompleter.isCompleted) {
        timeoutCompleter.completeError(TimeoutException('Gemma load timed out', timeout));
      }
    });

    try {
      final loadFuture = gemmaLoader != null
          ? gemmaLoader!()
          : (!gemmaService.isLoaded ? gemmaService.load() : Future<void>.value());

      await Future.any([loadFuture, timeoutCompleter.future]);
      _warmAiTimer?.cancel();
      _warmAiTimer = null;

      aiStatus.value = const AiStatus.ready();
      isAiReady.value = true;
      return true;
    } on TimeoutException {
      _warmAiTimer?.cancel();
      _warmAiTimer = null;
      debugPrint('Gemma load timed out after $timeout');
      aiStatus.value = const AiStatus.unavailable('model not loaded');
      isAiReady.value = false;
      return false;
    } catch (e) {
      _warmAiTimer?.cancel();
      _warmAiTimer = null;
      debugPrint('Failed to warm Gemma: $e');
      aiStatus.value = const AiStatus.unavailable('model not loaded');
      isAiReady.value = false;
      return false;
    }
  }

  void resetAiForTesting() {
    _warmAiTimer?.cancel();
    _warmAiTimer = null;
    _warmAiInFlight = null;
    gemmaLoader = null;
    aiWarmTimeout = const Duration(seconds: 90);
    destinationResolveTimeout = const Duration(seconds: 20);
    aiStatus.value = const AiStatus.loading();
    isAiReady.value = false;
  }
}
