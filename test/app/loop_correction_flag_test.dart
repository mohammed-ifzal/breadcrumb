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
        await support.tap(
          tester,
          finish ? 'record-finish-start' : 'record-mark',
        );
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Joined to Entrance - loop closed'), findsOneWidget);
        if (!finish) await support.tap(tester, 'record-stop');
        // Frozen pre-D33 graph: one place and a measured four-step self corridor.
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
          final path = await saveLatestMap(
            saved!,
            documentsDirectory: () async => directory,
          );
          expect(await File(path).readAsBytes(), encodeMap(legacy).codeUnits);
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
    await support.tap(tester, 'record-finish-start');
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
