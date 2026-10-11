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
  testWidgets('large-error Mark No never corrects existing loop coordinates', (
    tester,
  ) async {
    final events = StreamController<Object>.broadcast(sync: true);
    addTearDown(events.close);
    final builder = MapBuilder();
    await tester.pumpWidget(
      MaterialApp(
        home: RecordScreen(
          mapBuilder: builder,
          events: events.stream,
          traceRecorder: support.MemoryWalkTrace(),
          save: (_) async => '/maps/latest.json',
        ),
      ),
    );
    await support.start(tester);
    for (var leg = 0; leg < 4; leg++) {
      for (var i = 0; i < (leg < 2 ? 10 : 1); i++) {
        events.add(c.StepEvent(i));
      }
      if (leg < 3) events.add(const c.TurnEvent(0, 90));
    }
    await tester.pumpAndSettle();
    final before = builder.snapshot();
    expect(
      builder.previewLoopClosure('Entrance')!.requiresConfirmation,
      isTrue,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('place-name')));
    await tester.enterText(
      find.byKey(const ValueKey('place-name')),
      'Entrance',
    );
    await tester.pump();
    await tap(tester, 'record-mark');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Join the loop?'), findsOneWidget);
    expect(
      find.text("Positions don't match well - join anyway?"),
      findsOneWidget,
    );
    await tap(tester, 'join-no');
    final after = builder.snapshot();
    for (final p in before.places.where((p) => p.id != c.hereId)) {
      expect(
        after.places.singleWhere((a) => a.id == p.id).toJson(),
        p.toJson(),
      );
    }
    expect(
      after.corridors.take(3).map((edge) => edge.toJson()).toList(),
      before.corridors.take(3).map((edge) => edge.toJson()).toList(),
    );
    expect(after.corridors.where((edge) => edge.to == after.start), isEmpty);
    final newPlace = after.places.singleWhere((p) => p.name == 'Entrance 2');
    // A new numbered place retains its measured position, never a join correction.
    expect(newPlace.x, before.places.last.x);
    expect(newPlace.y, before.places.last.y);
    expect(after.corridors.map((edge) => edge.steps), [10, 10, 1, 1, 0]);
    expect(after.corridors.map((edge) => edge.heading), [0, 90, 180, 270, 270]);
    expect(find.text('RECORDING'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

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
          await tap(tester, finish ? 'record-finish-start' : 'record-mark');
          expect(
            find.text("Positions don't match well - join anyway?"),
            findsOneWidget,
          );
          expect(
            builder.snapshot().toJson(),
            before,
            reason: 'Preview must not consume steps',
          );
          expect(find.byType(AlertDialog), findsOneWidget);
          await tap(
            tester,
            finish
                ? (yes ? 'finish-yes' : 'finish-no')
                : (yes ? 'join-yes' : 'join-no'),
          );
          if (yes) {
            expect(
              find.text('Joined to Entrance - loop closed'),
              findsOneWidget,
            );
            if (!finish) {
              await tap(tester, 'record-stop');
              await tap(tester, 'stop-yes');
            }
            expect(saved, isNotNull);
            expect(saved!.corridors.single.to, saved!.start);
            expect(saved!.corridors.single.steps, 4);
            expect(saved!.places.single.x, 0);
            expect(decodeMap(encodeMap(saved!)).toJson(), saved!.toJson());
          } else {
            expect(saved, isNull);
            if (finish) {
              expect(builder.snapshot().toJson(), before);
            } else {
              final after = builder.snapshot();
              final oldPlaces = (before['places'] as List)
                  .where((p) => (p as Map)['id'] != c.hereId)
                  .toList();
              expect(
                after.places
                    .where((p) => p.id == 'p0')
                    .map((p) => p.toJson())
                    .toList(),
                oldPlaces,
              );
              final newPlace = after.places.singleWhere(
                (p) => p.name == 'Entrance 2',
              );
              expect(newPlace.x, 0);
              expect(newPlace.y, 4);
              expect(after.corridors.first.to, newPlace.id);
              expect(
                after.corridors.where((edge) => edge.to == after.start),
                isEmpty,
              );
              expect(after.corridors.first.steps, 4);
              expect(after.corridors.first.heading, 0);
              expect(find.text('Marked place: Entrance 2'), findsOneWidget);
            }
            expect(find.text('RECORDING'), findsOneWidget);
            events.add(const c.StepEvent(5));
            await tester.pumpAndSettle();
            expect(tester.widget<Text>(find.byKey(const ValueKey('record-steps'))).data, '5');
            expect(
              builder.snapshot().corridors.fold<int>(
                0,
                (sum, edge) => sum + edge.steps,
              ),
              5,
            );
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        },
      );
    }
  }
  testWidgets(
    'Finish at start applies small drift correction with only main confirmation',
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
      await tap(tester, 'record-finish-start');
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text("Positions don't match well - join anyway?"),
        findsNothing,
      );
      expect(find.text('Finish at Entrance?'), findsOneWidget);
      await tap(tester, 'finish-yes');
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
