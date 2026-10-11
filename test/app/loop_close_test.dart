import 'dart:async';
import 'dart:ui' as ui;

import 'package:breadcrumb/app/screens/record_screen.dart';
import 'package:breadcrumb/app/widgets/trail_view.dart';
import 'package:breadcrumb/core/contracts.dart' as c;
import 'package:breadcrumb/core/map_builder.dart';
import 'package:breadcrumb/core/trail_geometry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'record_screen_test.dart' as support;

void main() {
  testWidgets(
    'TrailView builds and paints a closed square loop without exception',
    (tester) async {
      const map = c.MapGraph(
        name: 'Closed square',
        start: 'start',
        places: [
          c.Place(id: 'start', name: 'Entrance', kind: c.PlaceKind.start),
          c.Place(id: 'j1', name: '', kind: c.PlaceKind.junction),
          c.Place(id: 'j2', name: '', kind: c.PlaceKind.junction),
          c.Place(id: 'j3', name: '', kind: c.PlaceKind.junction),
        ],
        corridors: [
          c.Corridor(id: 'c1', from: 'start', to: 'j1', steps: 5, heading: 0),
          c.Corridor(id: 'c2', from: 'j1', to: 'j2', steps: 5, heading: 90),
          c.Corridor(id: 'c3', from: 'j2', to: 'j3', steps: 5, heading: 180),
          c.Corridor(id: 'c4', from: 'j3', to: 'start', steps: 5, heading: 270),
        ],
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: TrailView(map: map, animate: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TrailView), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(map.corridors.last.to, map.start);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'duplicate mark joins existing node and shows loop-closed message',
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
      events.add(const c.StepEvent(1));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('place-name')),
        ' ENTRANCE ',
      );
      await tester.pump();
      await support.tap(tester, 'record-mark');
      if (find.byKey(const ValueKey('loop-join-yes')).evaluate().isNotEmpty) {
        await support.tap(tester, 'loop-join-yes');
      }
      expect(find.text('Joined to Entrance - loop closed'), findsOneWidget);
      final live = tester
          .widget<TrailView>(find.byType(TrailView))
          .mapNotifier!
          .value;
      expect(live.corridors.first.to, live.start);
      expect(live.places.where((p) => p.name == 'Entrance'), hasLength(1));
      await support.tap(tester, 'record-stop');
      expect(saved!.places.where((p) => p.name == 'End of walk'), isEmpty);
      expect(saved!.corridors.last.to, saved!.start);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
  for (final steps in [0, 3]) {
    testWidgets(
      'Finish at start closes and saves without extra endpoint ($steps steps)',
      (tester) async {
        final events = StreamController<Object>.broadcast(sync: true);
        addTearDown(events.close);
        final trace = support.MemoryWalkTrace();
        c.MapGraph? saved;
        await tester.pumpWidget(
          MaterialApp(
            home: RecordScreen(
              events: events.stream,
              traceRecorder: trace,
              save: (map) async {
                saved = map;
                return '/maps/latest.json';
              },
            ),
          ),
        );
        await support.start(tester);
        for (var i = 0; i < steps; i++) {
          events.add(c.StepEvent(i));
        }
        await tester.pumpAndSettle();
        await support.tap(tester, 'record-finish-start');
        if (find.byKey(const ValueKey('loop-join-yes')).evaluate().isNotEmpty) {
          await support.tap(tester, 'loop-join-yes');
        }
        expect(find.text('Joined to Entrance - loop closed'), findsOneWidget);
        expect(find.text('Saved map: /maps/latest.json'), findsOneWidget);
        expect(saved!.places.where((p) => p.name == 'End of walk'), isEmpty);
        expect(saved!.places, hasLength(1));
        if (steps == 0) {
          expect(saved!.corridors, isEmpty);
        } else {
          expect(saved!.corridors.single.to, saved!.start);
          expect(saved!.corridors.single.steps, steps);
        }
        expect(trace.stops, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
  test(
    'TrailView paints closing corridor as a line to the existing start',
    () async {
      const places = [
        c.Place(id: 's', name: 'Start', kind: c.PlaceKind.start),
        c.Place(id: 'a', name: '', kind: c.PlaceKind.junction),
        c.Place(id: 'b', name: '', kind: c.PlaceKind.junction),
        c.Place(id: 'd', name: '', kind: c.PlaceKind.junction),
      ];
      const edges = [
        c.Corridor(id: '1', from: 's', to: 'a', steps: 10, heading: 0),
        c.Corridor(id: '2', from: 'a', to: 'b', steps: 10, heading: 90),
        c.Corridor(id: '3', from: 'b', to: 'd', steps: 10, heading: 180),
        c.Corridor(id: '4', from: 'd', to: 's', steps: 10, heading: 270),
      ];
      const closed = c.MapGraph(
        name: 'Loop',
        start: 's',
        places: places,
        corridors: edges,
      );
      final open = c.MapGraph(
        name: 'Loop',
        start: 's',
        places: places,
        corridors: edges.take(3).toList(),
      );
      final points = layoutMap(closed);
      expect(points.map((p) => p.placeId).toSet(), {'s', 'a', 'b', 'd'});
      final painter = TrailPainter(closed, null, null);
      final end = points.singleWhere((p) => p.placeId == 's');
      final from = points.singleWhere((p) => p.placeId == 'd');
      const size = Size(400, 400);
      final midpoint = painter.toOffset(
        (from.x + end.x) / 2,
        (from.y + end.y) / 2,
        size,
      );
      Future<List<int>> pixel(c.MapGraph map) async {
        final recorder = ui.PictureRecorder();
        TrailPainter(map, null, null).paint(Canvas(recorder), size);
        final picture = recorder.endRecording();
        final image = await picture.toImage(400, 400);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final offset = (midpoint.dy.round() * 400 + midpoint.dx.round()) * 4;
        final result = bytes.buffer.asUint8List().sublist(offset, offset + 4);
        image.dispose();
        picture.dispose();
        return result;
      }

      expect(await pixel(closed), isNot(await pixel(open)));
    },
  );
}
