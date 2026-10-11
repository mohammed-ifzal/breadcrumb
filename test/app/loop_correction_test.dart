import 'dart:async';
import 'dart:io';

import 'package:breadcrumb/app/screens/record_screen.dart';
import 'package:breadcrumb/app/widgets/trail_view.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/core/contracts.dart' as c;
import 'package:breadcrumb/core/map_builder.dart';
import 'package:breadcrumb/core/map_json.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'record_screen_test.dart' as support;

void main() {
  test('approved demo fixture equals the existing built-in map', () async {
    expect(
      decodeMap(await File('assets/maps/demo_route.json').readAsString())
          .toJson(),
      Wiring.defaultDemoMap.toJson(),
    );
  });
  for (final finish in [false, true]) {
    for (final yes in [false, true]) {
      testWidgets(
        'large-error ${finish ? 'Finish at start' : 'Mark'}: ${yes ? 'Yes corrects and joins' : 'No keeps recording'}',
        (tester) async {
          final events = StreamController<Object>.broadcast(sync: true);
          addTearDown(events.close);
          final builder = MapBuilder();
          c.MapGraph? saved;
          await tester.pumpWidget(
            MaterialApp(
              home: RecordScreen(
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
            events.add(c.StepEvent(i));
          }
          await tester.pumpAndSettle();
          final before = builder.snapshot().toJson();
          if (!finish) {
            await tester.ensureVisible(
              find.byKey(const ValueKey('place-name')),
            );
            await tester.enterText(
              find.byKey(const ValueKey('place-name')),
              'Entrance',
            );
            await tester.pump();
          }
          await support.tap(
            tester,
            finish ? 'record-finish-start' : 'record-mark',
          );
          expect(
            find.text("Positions don't match well - join anyway?"),
            findsOneWidget,
          );
          expect(
            builder.snapshot().toJson(),
            before,
            reason: 'Preview must not consume steps',
          );
          await support.tap(tester, yes ? 'loop-join-yes' : 'loop-join-no');
          if (yes) {
            expect(
              find.text('Joined to Entrance - loop closed'),
              findsOneWidget,
            );
            if (!finish) await support.tap(tester, 'record-stop');
            expect(saved, isNotNull);
            expect(saved!.corridors.single.to, saved!.start);
            expect(saved!.corridors.single.steps, 4);
            expect(saved!.places.single.x, 0);
            expect(decodeMap(encodeMap(saved!)).toJson(), saved!.toJson());
          } else {
            expect(saved, isNull);
            expect(builder.snapshot().toJson(), before);
            expect(find.text('Recording trail'), findsOneWidget);
            events.add(const c.StepEvent(5));
            await tester.pumpAndSettle();
            expect(find.text('Steps: 5'), findsOneWidget);
            expect(builder.snapshot().corridors.single.steps, 5);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        },
      );
    }
  }
  testWidgets(
    'Finish at start applies small drift correction without a prompt',
    (tester) async {
      final events = StreamController<Object>.broadcast(sync: true);
      addTearDown(events.close);
      c.MapGraph? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: RecordScreen(
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
      for (var leg = 0; leg < 4; leg++) {
        for (var i = 0; i < (leg == 3 ? 7 : 10); i++) {
          events.add(c.StepEvent(leg * 100 + i));
        }
        if (leg < 3) events.add(c.TurnEvent(leg * 100 + 50, 90));
      }
      await tester.pumpAndSettle();
      await support.tap(tester, 'record-finish-start');
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        saved!.places.singleWhere((p) => p.id == 'j1').x,
        closeTo(30 / 37, 1e-9),
      );
      expect(saved!.corridors.map((c) => c.steps), [10, 10, 10, 7]);
      expect(saved!.corridors.map((c) => c.heading), [0, 90, 180, 270]);
      final map = tester
          .widget<TrailView>(find.byType(TrailView))
          .mapNotifier!
          .value;
      expect(map.toJson(), saved!.toJson());
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
