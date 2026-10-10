import 'dart:async';
import 'dart:io';

import 'package:breadcrumb/app/screens/record_debug_main.dart';
import 'package:breadcrumb/app/screens/record_screen.dart';
import 'package:breadcrumb/app/widgets/trail_view.dart';
import 'package:breadcrumb/core/contracts.dart' as contracts;
import 'package:breadcrumb/core/map_builder.dart';
import 'package:breadcrumb/core/map_json.dart';
import 'package:breadcrumb/sensing/trace_recorder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> tap(WidgetTester tester, String key) async {
  final button = find.byKey(ValueKey(key));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> start(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('start-name')),
    ' Entrance ',
  );
  await tester.pump();
  await tap(tester, 'record-start');
}

void main() {
  testWidgets('every walk opens a trace, records marks and closes at Stop', (
    tester,
  ) async {
    final trace = MemoryWalkTrace();
    final events = StreamController<Object>.broadcast(sync: true);
    addTearDown(events.close);
    await tester.pumpWidget(
      MaterialApp(
        home: RecordScreen(
          traceRecorder: trace,
          events: events.stream,
          save: (_) async => '/maps/latest.json',
        ),
      ),
    );
    await start(tester);
    expect(trace.starts, 1);
    expect(trace.rows.first['type'], 'meta');
    events.add(const contracts.StepEvent(20));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('place-name')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('place-name')), 'Desk');
    await tester.pump();
    await tap(tester, 'record-mark');
    events.add(const contracts.StepEvent(40));
    await tester.pumpAndSettle();
    await tap(tester, 'record-stop');
    expect(trace.stops, 1);
    expect(trace.state.value.recording, isFalse);
    expect(trace.rows.where((r) => r['type'] == 'mark').map((r) => r['note']), [
      'Desk',
      'End of walk',
    ]);
    expect(find.text('Trace file: ${MemoryWalkTrace.path}'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(trace.stops, 1);
  });
  testWidgets('map save failure still closes the trace and shows its path', (
    tester,
  ) async {
    final trace = MemoryWalkTrace();
    final events = StreamController<Object>.broadcast(sync: true);
    addTearDown(events.close);
    await tester.pumpWidget(
      MaterialApp(
        home: RecordScreen(
          traceRecorder: trace,
          events: events.stream,
          save: (_) async => throw const FileSystemException('map disk full'),
        ),
      ),
    );
    await start(tester);
    await tap(tester, 'record-stop');
    expect(trace.stops, 1);
    expect(trace.state.value.recording, isFalse);
    expect(find.textContaining('map disk full'), findsOneWidget);
    expect(find.text('Trace file: ${MemoryWalkTrace.path}'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets(
    'trace failures log once and never stop live counts or map saving',
    (tester) async {
      final trace = MemoryWalkTrace(failWrite: true, failStop: true);
      final events = StreamController<Object>.broadcast(sync: true);
      addTearDown(events.close);
      final messages = <String>[];
      final previous = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) messages.add(message);
      };
      addTearDown(() => debugPrint = previous);
      await tester.pumpWidget(
        MaterialApp(
          home: RecordScreen(
            traceRecorder: trace,
            events: events.stream,
            save: (_) async => '/maps/latest.json',
          ),
        ),
      );
      await start(tester);
      events.add(const contracts.StepEvent(20));
      events.add(const contracts.StepEvent(40));
      await tester.pumpAndSettle();
      expect(find.text('Steps: 2'), findsOneWidget);
      await tap(tester, 'record-stop');
      expect(find.text('Saved map: /maps/latest.json'), findsOneWidget);
      expect(
        messages.where((m) => m.contains('Trace recording failed')),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      debugPrint = previous;
    },
  );
  testWidgets('leaving an active walk also closes its trace', (tester) async {
    final trace = MemoryWalkTrace();
    final events = StreamController<Object>.broadcast(sync: true);
    addTearDown(events.close);
    await tester.pumpWidget(
      MaterialApp(
        home: RecordScreen(
          traceRecorder: trace,
          events: events.stream,
          save: (_) async => '/maps/latest.json',
        ),
      ),
    );
    await start(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(trace.stops, 1);
    expect(trace.state.value.recording, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'start precedes snapshot; every step, turn and mark publishes a map',
    (tester) async {
      final builder = CountingBuilder();
      final events = StreamController<Object>.broadcast(sync: true);
      addTearDown(events.close);
      await tester.pumpWidget(
        MaterialApp(
          home: RecordScreen(
            traceRecorder: MemoryWalkTrace(),
            mapBuilder: builder,
            events: events.stream,
            save: (_) async => '/maps/latest.json',
          ),
        ),
      );
      expect(find.byType(TrailView), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('record-start')))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byKey(const ValueKey('start-name')), '   ');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('record-start')))
            .onPressed,
        isNull,
      );
      await start(tester);
      expect(builder.snapshotCalls, 1);
      final notifier = tester
          .widget<TrailView>(find.byType(TrailView))
          .mapNotifier!;
      var updates = 0;
      notifier.addListener(() => updates++);
      events.add(const contracts.StepEvent(20));
      events.add(const contracts.StepEvent(40));
      events.add(const contracts.TurnEvent(60, 89));
      events.add(const contracts.StepEvent(80));
      await tester.pumpAndSettle();
      expect(find.text('Steps: 3'), findsOneWidget);
      expect(find.text('Last turn: +89.0° (left)'), findsOneWidget);
      expect(notifier.value.places.last.id, contracts.hereId);
      expect(notifier.value.corridors.last.heading, 90);
      expect(notifier.value.corridors.last.steps, 1);
      expect(updates, 4);
      final mark = find.byKey(const ValueKey('record-mark'));
      expect(tester.widget<FilledButton>(mark).onPressed, isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('place-name')));
      await tester.enterText(
        find.byKey(const ValueKey('place-name')),
        '  Coffee  ',
      );
      await tester.pump();
      await tap(tester, 'record-mark');
      expect(
        notifier.value.places.singleWhere((p) => p.name == 'Coffee').aliases,
        isEmpty,
      );
      expect(notifier.value.places.last.id, contracts.hereId);
      expect(notifier.value.corridors.last.steps, 0);
      expect(updates, 5);
      expect(builder.snapshotCalls, 6);
      expect(tester.widget<FilledButton>(mark).onPressed, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stop saves a round-trippable finished map and stops sensor updates',
    (tester) async {
      var cancels = 0;
      final events = StreamController<Object>.broadcast(
        sync: true,
        onCancel: () => cancels++,
      );
      addTearDown(events.close);
      String? written;
      var saves = 0;
      final saved = Completer<String>();
      await tester.pumpWidget(
        MaterialApp(
          home: RecordScreen(
            traceRecorder: MemoryWalkTrace(),
            events: events.stream,
            save: (map) {
              saves++;
              written = encodeMap(map);
              return saved.future;
            },
          ),
        ),
      );
      await start(tester);
      events.add(const contracts.StepEvent(20));
      events.add(const contracts.StepEvent(40));
      await tester.pumpAndSettle();
      await tap(tester, 'record-stop');
      expect(saves, 1);
      expect(cancels, 1);
      final map = decodeMap(written!);
      expect(map.name, 'Entrance');
      expect(map.corridors.single.steps, 2);
      expect(map.places.last.name, 'End of walk');
      expect(map.places.last.kind, contracts.PlaceKind.place);
      expect(map.places.any((p) => p.id == contracts.hereId), isFalse);
      expect(decodeMap(encodeMap(map)).toJson(), map.toJson());
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('record-stop')))
            .onPressed,
        isNull,
      );
      events.add(const contracts.StepEvent(60));
      saved.complete('/documents/maps/latest.json');
      await tester.pumpAndSettle();
      expect(find.text('Steps: 2'), findsOneWidget);
      expect(
        find.text('Saved map: /documents/maps/latest.json'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(cancels, 1);
    },
  );

  testWidgets(
    'save failure shows an error and allows retry without finishing twice',
    (tester) async {
      final builder = CountingBuilder();
      final events = StreamController<Object>.broadcast(sync: true);
      addTearDown(events.close);
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: RecordScreen(
            traceRecorder: MemoryWalkTrace(),
            mapBuilder: builder,
            events: events.stream,
            save: (_) async {
              if (++saves == 1) throw const FileSystemException('disk full');
              return '/documents/maps/latest.json';
            },
          ),
        ),
      );
      await start(tester);
      events.add(const contracts.StepEvent(20));
      await tester.pumpAndSettle();
      await tap(tester, 'record-stop');
      expect(find.textContaining('disk full'), findsOneWidget);
      expect(find.text('Retry save'), findsOneWidget);
      expect(builder.finishCalls, 1);
      expect(builder.endPlaceCalls, 1);
      expect(tester.takeException(), isNull);
      await tap(tester, 'record-stop');
      expect(saves, 2);
      expect(builder.finishCalls, 1);
      expect(builder.endPlaceCalls, 1);
      expect(find.textContaining('disk full'), findsNothing);
      expect(
        find.text('Saved map: /documents/maps/latest.json'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  for (final stepsAfterMark in [0, 1]) {
    testWidgets('D23 Stop after mark with $stepsAfterMark extra steps', (
      tester,
    ) async {
      final events = StreamController<Object>.broadcast(sync: true);
      addTearDown(events.close);
      contracts.MapGraph? savedMap;
      await tester.pumpWidget(
        MaterialApp(
          home: RecordScreen(
            traceRecorder: MemoryWalkTrace(),
            events: events.stream,
            save: (map) async {
              savedMap = map;
              return '/maps/latest.json';
            },
          ),
        ),
      );
      await start(tester);
      events.add(const contracts.StepEvent(20));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('place-name')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('place-name')), 'Desk');
      await tester.pump();
      await tap(tester, 'record-mark');
      for (var i = 0; i < stepsAfterMark; i++) {
        events.add(contracts.StepEvent(40 + i * 20));
      }
      await tester.pumpAndSettle();
      await tap(tester, 'record-stop');
      final map = savedMap!;
      expect(map.places.last.kind, contracts.PlaceKind.place);
      if (stepsAfterMark == 0) {
        expect(map.places.last.name, 'Desk');
        expect(map.places.where((p) => p.name == 'End of walk'), isEmpty);
        expect(map.corridors.map((c) => c.steps), [1]);
      } else {
        expect(map.places.last.name, 'End of walk');
        expect(map.corridors.map((c) => c.steps), [1, 1]);
      }
      expect(decodeMap(encodeMap(map)).toJson(), map.toJson());
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets('D23 Stop with zero steps still adds a named End of walk', (
    tester,
  ) async {
    final events = StreamController<Object>.broadcast(sync: true);
    addTearDown(events.close);
    contracts.MapGraph? savedMap;
    await tester.pumpWidget(
      MaterialApp(
        home: RecordScreen(
          traceRecorder: MemoryWalkTrace(),
          events: events.stream,
          save: (map) async {
            savedMap = map;
            return '/maps/latest.json';
          },
        ),
      ),
    );
    await start(tester);
    await tap(tester, 'record-stop');
    final map = savedMap!;
    expect(map.places.map((p) => p.name), ['Entrance', 'End of walk']);
    expect(map.places.last.kind, contracts.PlaceKind.place);
    expect(map.corridors.single.steps, 0);
    expect(map.corridors.single.to, map.places.last.id);
    expect(map.places.any((p) => p.id == contracts.hereId), isFalse);
    expect(decodeMap(encodeMap(map)).toJson(), map.toJson());
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  testWidgets('dispose cancels subscriptions and disposes the map notifier', (
    tester,
  ) async {
    var cancels = 0;
    final events = StreamController<Object>.broadcast(
      sync: true,
      onCancel: () => cancels++,
    );
    addTearDown(events.close);
    await tester.pumpWidget(
      MaterialApp(
        home: RecordScreen(
          traceRecorder: MemoryWalkTrace(),
          events: events.stream,
          save: (_) async => '/maps/latest.json',
        ),
      ),
    );
    await start(tester);
    final notifier = tester
        .widget<TrailView>(find.byType(TrailView))
        .mapNotifier!;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(cancels, 1);
    expect(() => notifier.addListener(() {}), throwsFlutterError);
    events.add(const contracts.StepEvent(20));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('sensor errors are shown and the partial map remains saveable', (
    tester,
  ) async {
    final events = StreamController<Object>.broadcast(sync: true);
    addTearDown(events.close);
    await tester.pumpWidget(
      MaterialApp(
        home: RecordScreen(
          traceRecorder: MemoryWalkTrace(),
          events: events.stream,
          save: (_) async => '/maps/latest.json',
        ),
      ),
    );
    await start(tester);
    events.add(const contracts.StepEvent(20));
    events.addError(StateError('sensor disconnected'));
    await tester.pumpAndSettle();
    expect(find.textContaining('sensor disconnected'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tap(tester, 'record-stop');
    expect(find.text('Saved map: /maps/latest.json'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'large text scrolls without overflow and reduced motion skips animations',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final events = StreamController<Object>.broadcast(sync: true);
      addTearDown(events.close);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(2.5),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: RecordScreen(
            traceRecorder: MemoryWalkTrace(),
            events: events.stream,
            save: (_) async => '/documents/maps/latest.json',
          ),
        ),
      );
      await start(tester);
      events.add(const contracts.StepEvent(20));
      await tester.pumpAndSettle();
      expect(find.byType(SafeArea), findsWidgets);
      expect(find.byType(SingleChildScrollView), findsWidgets);
      for (final widget in tester.widgetList<AnimatedSwitcher>(
        find.byType(AnimatedSwitcher),
      )) {
        expect(widget.duration, Duration.zero);
      }
      await tap(tester, 'record-stop');
      expect(
        find.text('Saved map: /documents/maps/latest.json'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'standalone record app builds before hardware or documents are accessed',
    (tester) async {
      await tester.pumpWidget(const RecordDebugApp());
      expect(find.byType(RecordScreen), findsOneWidget);
      expect(find.text('Record a trail'), findsOneWidget);
      expect(find.byType(TrailView), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  test('default save creates maps/latest.json, round-trips and replaces prior content', () async {
    final directory = await Directory.systemTemp.createTemp(
      'breadcrumb-record-save-',
    );
    try {
      final builder = MapBuilder()..start('First');
      builder.onStep(const contracts.StepEvent(20));
      final first = builder.finish();
      final path = await saveLatestMap(
        first,
        documentsDirectory: () async => directory,
      );
      expect(
        path,
        '${directory.path}${Platform.pathSeparator}maps${Platform.pathSeparator}latest.json',
      );
      expect(
        decodeMap(await File(path).readAsString()).toJson(),
        first.toJson(),
      );
      builder.start('Second');
      builder.addPlace('Desk', []);
      final second = builder.finish();
      expect(
        await saveLatestMap(second, documentsDirectory: () async => directory),
        path,
      );
      expect(
        decodeMap(await File(path).readAsString()).toJson(),
        second.toJson(),
      );
      expect(
        directory.listSync(recursive: true).whereType<File>(),
        hasLength(1),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });
}

class CountingBuilder extends MapBuilder {
  int snapshotCalls = 0;
  int finishCalls = 0;
  int endPlaceCalls = 0;
  @override
  void addPlace(String name, List<String> aliases) {
    if (name == 'End of walk') endPlaceCalls++;
    super.addPlace(name, aliases);
  }

  @override
  contracts.MapGraph snapshot() {
    snapshotCalls++;
    return super.snapshot();
  }

  @override
  contracts.MapGraph finish() {
    finishCalls++;
    return super.finish();
  }
}

class MemoryWalkTrace extends TraceRecorder {
  MemoryWalkTrace({this.failWrite = false, this.failStop = false});
  static const path = '/documents/traces/walk.jsonl';
  final bool failWrite, failStop;
  int starts = 0, stops = 0;
  final rows = <Map<String, Object?>>[];
  @override
  Future<void> start(Map<String, Object?> meta) async {
    starts++;
    rows.add({...meta, 'type': 'meta'});
    state.value = const TraceState(recording: true, path: path);
  }

  @override
  void record(Map<String, Object?> event) {
    if (failWrite) throw const FileSystemException('trace disk full');
    if (state.value.recording) rows.add(Map.of(event));
  }

  @override
  Future<void> finalizeMetadata(Map<String, Object?> fields) async {
    if (rows.isNotEmpty) rows[0].addAll(fields);
  }

  @override
  Future<void> stop() async {
    stops++;
    state.value = const TraceState(path: path);
    if (failStop) throw const FileSystemException('trace close failed');
  }
}
