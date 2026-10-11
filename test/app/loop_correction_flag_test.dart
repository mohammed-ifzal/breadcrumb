import 'dart:async';
import 'dart:io';

import 'package:breadcrumb/app/screens/record_screen.dart';
import 'package:breadcrumb/app/widgets/trail_view.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/map_builder.dart' as recording;
import 'package:breadcrumb/core/map_json.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'record_screen_test.dart' as support;

/// Tap without the main test helper's automatic Stop/Finish confirmation.
/// These regressions inspect that same dialog and choose its answer explicitly.
Future<void> tap(WidgetTester tester, String key) async {
  final button = find.byKey(ValueKey(key));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  for (final finish in [false, true]) {
    testWidgets(
      'flag off: ${finish ? "Finish at start" : "Mark"} saves legacy bytes without a drift prompt',
      (tester) async {
        final directory = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('loop_flag_'),
        ))!;
        addTearDown(() => directory.delete(recursive: true));
        final events = StreamController<Object>.broadcast(sync: true);
        addTearDown(events.close);
        MapGraph? saved;
        await tester.pumpWidget(
          MaterialApp(
            home: RecordScreen(
              useLoopCorrection: false,
              events: events.stream,
              traceRecorder: support.MemoryWalkTrace(),
              save: (map) async {
                saved = map;
                return '/maps/latest.json';
              },
            ),
          ),
        );
        await support.start(tester);
        for (var i = 0; i < 4; i++) {
          events.add(StepEvent(i));
        }
        await tester.pumpAndSettle();
        if (!finish) {
          await tester.ensureVisible(find.byKey(const ValueKey('place-name')));
          await tester.enterText(
            find.byKey(const ValueKey('place-name')),
            ' entrance ',
          );
          await tester.pump();
        }
        await tap(tester, finish ? 'record-finish-start' : 'record-mark');
        expect(find.byType(AlertDialog), findsOneWidget);
        final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
        expect(
          (dialog.title! as Text).data,
          finish ? 'Finish at Entrance?' : 'Join the loop?',
        );
        expect(
          (dialog.content! as Text).data,
          finish ? 'This joins the loop at Entrance and saves the map.' : "A place called 'Entrance' already exists. Connect this point to it?",
        );
        expect(dialog.actions, hasLength(2));
        expect(
          (dialog.actions![0] as TextButton).key,
          ValueKey(finish ? 'finish-no' : 'join-no'),
        );
        expect(
          ((dialog.actions![0] as TextButton).child as Text).data,
          finish ? 'Keep recording' : "Save as 'Entrance 2'",
        );
        expect(
          (dialog.actions![1] as FilledButton).key,
          ValueKey(finish ? 'finish-yes' : 'join-yes'),
        );
        expect(
          ((dialog.actions![1] as FilledButton).child as Text).data,
          finish ? 'Finish and save' : 'Join loop',
        );
        expect(
          find.text("Positions don't match well - join anyway?"),
          findsNothing,
        );
        await tap(tester, finish ? 'finish-yes' : 'join-yes');
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Joined to Entrance - loop closed'), findsOneWidget);
        if (!finish) {
          await tap(tester, 'record-stop');
          expect(find.text('Stop and save this map?'), findsOneWidget);
          await tap(tester, 'stop-yes');
        }
        // Frozen pre-D34 graph: one place and a measured four-step self corridor.
        final legacy = MapGraph(
          name: 'Entrance',
          start: 'p0',
          places: const [
            Place(id: 'p0', name: 'Entrance', kind: PlaceKind.start),
          ],
          corridors: const [
            Corridor(id: 'c1', from: 'p0', to: 'p0', steps: 4, heading: 0),
          ],
        );
        await tester.runAsync(() async {
          final path = await saveRecordedMap(
            saved!,
            documentsDirectory: () async => directory,
          );
          expect(await File(path).readAsBytes(), encodeMap(legacy).codeUnits);
          expect(
            await File('${directory.path}/maps/latest.json').readAsBytes(),
            encodeMap(legacy).codeUnits,
          );
          expect(
            await File('${directory.path}/maps/active.txt').readAsString(),
            File(path).uri.pathSegments.last,
          );
        });
        final drawn = tester
            .widget<TrailView>(find.byType(TrailView))
            .mapNotifier!
            .value;
        expect(encodeMap(drawn), encodeMap(legacy));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  for (final finish in [false, true]) {
    testWidgets(
      'flag off: main No behaviour for ${finish ? "Finish" : "Mark"}',
      (tester) async {
        final events = StreamController<Object>.broadcast(sync: true);
        addTearDown(events.close);
        final builder = recording.MapBuilder(useLoopCorrection: false);
        MapGraph? saved;
        await tester.pumpWidget(
          MaterialApp(
            home: RecordScreen(
              useLoopCorrection: false,
              mapBuilder: builder,
              events: events.stream,
              traceRecorder: support.MemoryWalkTrace(),
              save: (map) async {
                saved = map;
                return '/maps/latest.json';
              },
            ),
          ),
        );
        await support.start(tester);
        for (var i = 0; i < 4; i++) {
          events.add(StepEvent(i));
        }
        await tester.pumpAndSettle();
        final before = encodeMap(builder.snapshot());
        if (!finish) {
          await tester.ensureVisible(find.byKey(const ValueKey('place-name')));
          await tester.enterText(
            find.byKey(const ValueKey('place-name')),
            'Entrance',
          );
          await tester.pump();
        }
        await tap(tester, finish ? 'record-finish-start' : 'record-mark');
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          find.text("Positions don't match well - join anyway?"),
          findsNothing,
        );
        await tap(tester, finish ? 'finish-no' : 'join-no');
        expect(saved, isNull);
        expect(find.text('RECORDING'), findsOneWidget);
        if (finish) {
          expect(encodeMap(builder.snapshot()), before);
          events.add(const StepEvent(5));
          await tester.pumpAndSettle();
          expect(tester.widget<Text>(find.byKey(const ValueKey('record-steps'))).data, '5');
        } else {
          expect(find.text('Marked place: Entrance 2'), findsOneWidget);
          await tap(tester, 'record-stop');
          expect(find.text('Stop and save this map?'), findsOneWidget);
          await tap(tester, 'stop-yes');
          final legacy = MapGraph(
            name: 'Entrance',
            start: 'p0',
            places: const [
              Place(id: 'p0', name: 'Entrance', kind: PlaceKind.start),
              Place(id: 'p1', name: 'Entrance 2', kind: PlaceKind.place),
            ],
            corridors: const [
              Corridor(id: 'c1', from: 'p0', to: 'p1', steps: 4, heading: 0),
            ],
          );
          expect(encodeMap(saved!), encodeMap(legacy));
        }
        expect(
          builder.snapshot().places.every((p) => p.x == null && p.y == null),
          isTrue,
        );
        expect(
          builder.snapshot().corridors.where((c) => c.to == 'p0'),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
  testWidgets('injected flag-off builder also skips drift confirmation', (
    tester,
  ) async {
    final events = StreamController<Object>.broadcast(sync: true);
    addTearDown(events.close);
    await tester.pumpWidget(
      MaterialApp(
        home: RecordScreen(
          mapBuilder: recording.MapBuilder(useLoopCorrection: false),
          events: events.stream,
          traceRecorder: support.MemoryWalkTrace(),
          save: (_) async => '/maps/latest.json',
        ),
      ),
    );
    await support.start(tester);
    events.add(const StepEvent(0));
    await tester.pumpAndSettle();
    await tap(tester, 'record-finish-start');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text("Positions don't match well - join anyway?"),
      findsNothing,
    );
    await tap(tester, 'finish-yes');
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
