import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:breadcrumb/app/screens/record_screen.dart';
import 'package:breadcrumb/app/widgets/trail_view.dart';
import 'package:breadcrumb/core/contracts.dart' as contracts;
import 'package:breadcrumb/core/map_builder.dart';
import 'package:breadcrumb/core/map_json.dart';
import 'package:breadcrumb/sensing/trace_recorder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/record_screen_test.dart' show confirmIfAsked;

class WalkSource implements contracts.SensingSource {
  WalkSource({this.recorder});
  final TraceRecorder? recorder;
  final ready = Completer<void>();
  final closed = Completer<void>();
  final controller = StreamController<Object>.broadcast(sync: true);
  final marks = <String>[];
  bool tracing = false;
  int stops = 0;
  @override
  Stream<Object> events() => controller.stream;
  @override
  Future<void> startTrace(Map<String, Object?> meta) async {
    await recorder?.start(meta);
    tracing = true;
    ready.complete();
  }

  @override
  void mark(String note) {
    expect(tracing, isTrue);
    marks.add(note);
    recorder?.mark(0, note);
  }

  @override
  Future<void> stopTrace() async {
    tracing = false;
    stops++;
    await recorder?.stop();
    if (!closed.isCompleted) closed.complete();
  }

  // D29 compile stubs (captain, with the contract change).
  @override
  Stream<contracts.MotionStateEvent> motionStates() => const Stream.empty();
  @override
  Stream<contracts.PlacementEvent> placements() => const Stream.empty();
  @override
  Future<int> totalRamMb() async => 0;
}

Future<void> tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
  await confirmIfAsked(tester, key);
}

Future<WalkSource> begin(
  WidgetTester tester, {
  required Future<String> Function(contracts.MapGraph) save,
  WalkSource? injectedSource,
}) async {
  final source = injectedSource ?? WalkSource();
  addTearDown(source.controller.close);
  await tester.pumpWidget(
    MaterialApp(
      home: RecordScreen(
        mapBuilder: MapBuilder(),
        sensingSource: source,
        save: save,
      ),
    ),
  );
  expect(find.byKey(const ValueKey('record-floor')), findsNothing);
  await tester.enterText(find.byKey(const ValueKey('start-name')), 'Entrance');
  await tap(tester, 'record-start');
  expect(find.text('Current floor: 0'), findsOneWidget);
  return source;
}

Future<void> change(WidgetTester tester, String direction, String kind) async {
  await tap(tester, 'record-floor');
  expect(find.text('Change floor'), findsWidgets);
  await tap(tester, 'floor-$direction');
  expect(find.text('Choose transport'), findsOneWidget);
  await tap(tester, 'floor-$kind');
}

Future<void> waitForDisk(WidgetTester tester, bool Function() complete) async {
  // I/O started by the widget continues in its fake zone. Allow real I/O to
  // finish, then pump that zone's continuations; never await its future there.
  for (var attempt = 0; attempt < 250 && !complete(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(
    complete(),
    isTrue,
    reason: 'Trace I/O did not finish within five seconds',
  );
}

void main() {
  testWidgets('floor change is a JSONL mark even when saving the map fails', (
    tester,
  ) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('breadcrumb-floor-trace-'),
    ))!;
    final recorder = TraceRecorder(documentsDirectory: () async => directory);
    final source = WalkSource(recorder: recorder);
    try {
      await begin(
        tester,
        injectedSource: source,
        save: (_) async => throw const FileSystemException('map disk full'),
      );
      await waitForDisk(tester, () => source.ready.isCompleted);
      await change(tester, 'up', 'stairs');
      await tap(tester, 'record-stop');
      await waitForDisk(tester, () => source.closed.isCompleted);
      final text = await tester.runAsync(
        () => File(recorder.state.value.path!).readAsString(),
      );
      final rows = const LineSplitter()
          .convert(text!)
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();
      expect(rows.first['type'], 'meta');
      expect(
        rows.where((row) => row['type'] == 'mark').map((row) => row['note']),
        ['Floor change: up via stairs (Floor 0 -> Floor 1)', 'End of walk'],
      );
      expect(recorder.state.value.recording, isFalse);
      expect(find.textContaining('map disk full'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      var disposed = false;
      unawaited(recorder.dispose().then((_) => disposed = true));
      await waitForDisk(tester, () => disposed);
      await tester.runAsync(() => directory.delete(recursive: true));
    }
  });
  testWidgets(
    'Up then Stairs publishes floor 1 before any steps and Stop keeps D23',
    (tester) async {
      contracts.MapGraph? saved;
      final source = await begin(
        tester,
        save: (map) async {
          saved = map;
          return '/maps/latest.json';
        },
      );
      final notifier = tester
          .widget<TrailView>(find.byType(TrailView))
          .mapNotifier!;
      var updates = 0;
      notifier.addListener(() => updates++);
      await change(tester, 'up', 'stairs');
      expect(find.text('Current floor: 1'), findsOneWidget);
      expect(updates, 1);
      expect(notifier.value.places.last.id, contracts.hereId);
      expect(notifier.value.places.last.floor, 1);
      final transition = notifier.value.corridors.first;
      expect(
        (transition.kind, transition.floorDelta, transition.steps),
        (contracts.CorridorKind.stairs, 1, 0),
      );
      expect(source.marks, [
        'Floor change: up via stairs (Floor 0 -> Floor 1)',
      ]);
      await tap(tester, 'record-stop');
      expect(saved!.places.last.name, 'End of walk');
      expect(saved!.places.last.floor, 1);
      expect(decodeMap(encodeMap(saved!)).toJson(), saved!.toJson());
      expect(source.tracing, isFalse);
      expect(source.stops, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Down then Lift right after a turn publishes floor -1 and preserves heading',
    (tester) async {
      final source = await begin(
        tester,
        save: (_) async => '/maps/latest.json',
      );
      source.controller.add(const contracts.StepEvent(20));
      source.controller.add(const contracts.TurnEvent(40, 90));
      // D29: with useTurnConfirmer the turn counts once two steps follow it.
      source.controller.add(const contracts.StepEvent(500));
      source.controller.add(const contracts.StepEvent(1000));
      await tester.pumpAndSettle();
      final notifier = tester
          .widget<TrailView>(find.byType(TrailView))
          .mapNotifier!;
      var updates = 0;
      notifier.addListener(() => updates++);
      await change(tester, 'down', 'lift');
      expect(find.text('Current floor: -1'), findsOneWidget);
      expect(updates, 1);
      final transition = notifier.value.corridors
          .where((c) => c.isTransition)
          .single;
      expect(
        (transition.kind, transition.floorDelta, transition.heading),
        (contracts.CorridorKind.lift, -1, 90),
      );
      expect(
        source.marks.last,
        'Floor change: down via lift (Floor 0 -> Floor -1)',
      );
      await tester.enterText(
        find.byKey(const ValueKey('place-name')),
        'Lower lobby',
      );
      await tap(tester, 'record-mark');
      expect(
        notifier.value.places
            .where((p) => p.name == 'Lower lobby')
            .single
            .floor,
        -1,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(source.stops, 1);
    },
  );
  testWidgets(
    'two changes after a mark still add an endpoint on the final floor',
    (tester) async {
      contracts.MapGraph? saved;
      final source = await begin(
        tester,
        save: (map) async {
          saved = map;
          return '/maps/latest.json';
        },
      );
      await tester.enterText(
        find.byKey(const ValueKey('place-name')),
        'Ground desk',
      );
      await tap(tester, 'record-mark');
      await change(tester, 'up', 'escalator');
      await change(tester, 'up', 'lift');
      expect(find.text('Current floor: 2'), findsOneWidget);
      await tap(tester, 'record-stop');
      expect(saved!.places.last.name, 'End of walk');
      expect(saved!.places.last.floor, 2);
      expect(
        saved!.corridors.where((c) => c.isTransition).map((c) => c.floorDelta),
        [1, 1],
      );
      expect(
        source.marks.where((m) => m.startsWith('Floor change:')),
        hasLength(2),
      );
    },
  );
  testWidgets('a place marked after a floor change keeps the D23 exception', (
    tester,
  ) async {
    contracts.MapGraph? saved;
    await begin(
      tester,
      save: (map) async {
        saved = map;
        return '/maps/latest.json';
      },
    );
    await change(tester, 'up', 'stairs');
    await tester.enterText(find.byKey(const ValueKey('place-name')), 'Landing');
    await tap(tester, 'record-mark');
    await tap(tester, 'record-stop');
    expect(saved!.places.last.name, 'Landing');
    expect(saved!.places.last.floor, 1);
    expect(saved!.places.where((p) => p.name == 'End of walk'), isEmpty);
  });
  testWidgets(
    'cancelling either dialog leaves the floor and notifier unchanged',
    (tester) async {
      final source = await begin(
        tester,
        save: (_) async => '/maps/latest.json',
      );
      final notifier = tester
          .widget<TrailView>(find.byType(TrailView))
          .mapNotifier!;
      final before = notifier.value.toJson();
      await tap(tester, 'record-floor');
      await tap(tester, 'floor-cancel');
      await tap(tester, 'record-floor');
      await tap(tester, 'floor-up');
      await tap(tester, 'floor-cancel');
      expect(notifier.value.toJson(), before);
      expect(source.marks, isEmpty);
    },
  );
  testWidgets('map-save failure still closes the floor-change trace', (
    tester,
  ) async {
    final source = await begin(
      tester,
      save: (_) async => throw const FileSystemException('disk full'),
    );
    await change(tester, 'up', 'stairs');
    await tap(tester, 'record-stop');
    expect(find.textContaining('disk full'), findsOneWidget);
    expect(source.stops, 1);
    expect(source.tracing, isFalse);
    expect(tester.takeException(), isNull);
  });
}
