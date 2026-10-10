// ignore_for_file: avoid_print, prefer_interpolation_to_compose_strings
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/tracker.dart';
import 'package:breadcrumb/core/guide.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/app/speaker.dart';
import 'package:breadcrumb/app/screens/destination_list_screen.dart';
import 'package:breadcrumb/app/screens/navigate_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Prevent warmAi from creating a pending timer in tests.
    Wiring.instance.resetAiForTesting();
    Wiring.instance.aiStatus.value = const AiStatus.ready();
    Wiring.instance.isAiReady.value = true;
  });

  tearDown(() {
    Wiring.instance.resetAiForTesting();
  });

  group('BUG 1 Regressions', () {
    testWidgets('current place is never shown in destination list', (tester) async {
      final wiring = Wiring.instance;
      wiring.currentPlaceId = 'cafe';

      await tester.pumpWidget(const MaterialApp(home: DestinationListScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Cafe'), findsNothing);
      expect(find.text('Entrance'), findsOneWidget);

      wiring.currentPlaceId = null; // reset
    });

    testWidgets('zero-leg route shows "You\'re already at X" with back button', (tester) async {
      final wiring = Wiring.instance;
      wiring.currentPlaceId = 'entrance';

      await tester.pumpWidget(const MaterialApp(
        home: NavigateScreen(destinationId: 'entrance'),
      ));
      await tester.pumpAndSettle();

      expect(find.text("You're already at Entrance"), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Go Back'), findsOneWidget);
      wiring.currentPlaceId = null;
    });

    testWidgets('navigation builds without throwing for EVERY place as start and EVERY other place as destination', (tester) async {
      final wiring = Wiring.instance;
      final places = wiring.map.places;

      for (final start in places) {
        for (final dest in places) {
          wiring.currentPlaceId = start.id;

          await tester.pumpWidget(MaterialApp(
            home: NavigateScreen(destinationId: dest.id),
          ));
          await tester.pump();

          // Ensure widget built cleanly without unhandled exception
          expect(tester.takeException(), isNull);
        }
      }
      wiring.currentPlaceId = null;
    });
  });

  group('BUG 2 Regressions', () {
    testWidgets('BUG 2b: full walk of route with left and right turn vibrates exactly once per turn at the corner and once on arrival', (tester) async {
      final wiring = Wiring.instance;
      wiring.currentPlaceId = 'cafe';

      final recordedPatterns = <List<int>>[];
      final originalSpeaker = wiring.speaker;
      wiring.speaker = AppSpeaker(
        customVibrate: (pattern, duration) async {
          recordedPatterns.add(pattern);
        },
      );

      // Route: cafe -> stage (has left turn at j1, right turn at j2, arrival at stage)
      await tester.pumpWidget(const MaterialApp(
        home: NavigateScreen(destinationId: 'stage'),
      ));
      await tester.pump();

      // At start (stepsLeft = 10, > turnNowSteps 3): no vibration yet!
      expect(recordedPatterns, isEmpty);

      // Walk 6 steps on Leg 0 (steps along: 6, steps left: 4 > 3): still no vibration!
      for (int i = 0; i < 6; i++) {
        wiring.emitSimulatedEvent(StepEvent(100 * (i + 1)));
        await tester.pump();
      }
      expect(recordedPatterns, isEmpty);

      // Steps 7, 8, 9 on Leg 0: "Get ready to turn left" (stepsLeft 3..1): no vibration yet!
      for (int i = 7; i <= 9; i++) {
        wiring.emitSimulatedEvent(StepEvent(100 * i));
        await tester.pump();
      }
      expect(recordedPatterns, isEmpty);

      // Step 10 on Leg 0: stepsLeft = 0, "Turn left at the corner": FIRST turn vibration fires!
      wiring.emitSimulatedEvent(const StepEvent(1000));
      await tester.pump();
      expect(recordedPatterns.length, 1);
      expect(recordedPatterns.last, equals([0, 100, 100, 100])); // two short pulses for turnLeft

      // Turn left (+90) into Leg 1 (j1 -> j2, 20 steps heading 0)
      wiring.emitSimulatedEvent(const TurnEvent(1100, 90.0));
      await tester.pump();
      expect(recordedPatterns.length, 1);

      // Walk 16 steps along Leg 1 (steps along 16, steps left: 4 > 3): no vibration!
      for (int i = 1; i <= 16; i++) {
        wiring.emitSimulatedEvent(StepEvent(1100 + 100 * i));
        await tester.pump();
      }
      expect(recordedPatterns.length, 1);

      // Steps 17, 18, 19 on Leg 1: "Get ready to turn right": no vibration yet!
      for (int i = 17; i <= 19; i++) {
        wiring.emitSimulatedEvent(StepEvent(1100 + 100 * i));
        await tester.pump();
      }
      expect(recordedPatterns.length, 1);

      // Step 20 on Leg 1: stepsLeft = 0, "Turn right at the corner": SECOND turn vibration fires!
      wiring.emitSimulatedEvent(const StepEvent(3100));
      await tester.pump();
      expect(recordedPatterns.length, 2);
      expect(recordedPatterns.last, equals([0, 300])); // one long pulse for turnRight

      // Turn right (-90) into Leg 2 (j2 -> stage, 12 steps heading 270)
      wiring.emitSimulatedEvent(const TurnEvent(3200, -90.0));
      await tester.pump();
      expect(recordedPatterns.length, 2);

      // Walk 11 steps along Leg 2 (straight towards stage): straight NEVER vibrates!
      for (int i = 1; i <= 11; i++) {
        wiring.emitSimulatedEvent(StepEvent(3200 + 100 * i));
        await tester.pump();
      }
      expect(recordedPatterns.length, 2);

      // Step 12: arrival!
      wiring.emitSimulatedEvent(const StepEvent(4400));
      await tester.pump();
      expect(recordedPatterns.length, 3);
      expect(recordedPatterns.last, equals([0, 100, 100, 100, 100, 100])); // three short pulses for arrive

      // Reset
      wiring.speaker = originalSpeaker;
      wiring.currentPlaceId = null;
    });

    test('walk real planned routes step by step and print steps left, kind, text', () {
      final wiring = Wiring.instance;

      void walkRoute(String from, String to, String title) {
        print('=== $title ($from -> $to) ===');
        final route = wiring.planner.plan(wiring.map, from, to);
        final tracker = RouteTracker(wiring.map);
        final guide = RouteGuide(wiring.map);
        tracker.setRoute(route);
        tracker.anchor(from);

        var pos = tracker.position;
        var instr = guide.next(route, pos);
        print('[Start] leg=${pos.legIndex} stepsAlong=${pos.stepsAlong} | stepsLeft=${instr.steps}, kind=${instr.kind.name}, text="' + instr.text + '"');

        int t = 1000;
        for (int legIdx = 0; legIdx < route.legs.length; legIdx++) {
          final leg = route.legs[legIdx];
          for (int s = 0; s < leg.steps; s++) {
            t += 500;
            pos = tracker.onStep(StepEvent(t));
            instr = guide.next(route, pos);
            print('[Leg $legIdx step ${s + 1}/${leg.steps}] leg=${pos.legIndex} stepsAlong=${pos.stepsAlong} | stepsLeft=${instr.steps}, kind=${instr.kind.name}, text="' + instr.text + '"');
          }
          if (legIdx + 1 < route.legs.length) {
            final nextLeg = route.legs[legIdx + 1];
            final angle = turnBetween(leg.heading, nextLeg.heading);
            if (angle.abs() >= 30) {
              t += 500;
              pos = tracker.onTurn(TurnEvent(t, angle));
              instr = guide.next(route, pos);
              print('[Turn $angle°] leg=${pos.legIndex} stepsAlong=${pos.stepsAlong} | stepsLeft=${instr.steps}, kind=${instr.kind.name}, text="' + instr.text + '"');
            }
          }
        }
      }

      walkRoute('entrance', 'cafe', 'Entrance to Cafe (Left turn)');
      walkRoute('entrance', 'stage', 'Entrance to Stage (Right turn)');
    });

    test('fake vibrator records two short pulses for left turn, one long for right turn, three short for arrive', () async {
      final recordedPatterns = <List<int>>[];
      final recordedDurations = <int>[];

      final speaker = AppSpeaker(
        customVibrate: (pattern, duration) async {
          recordedPatterns.add(pattern);
          recordedDurations.add(duration);
        },
      );

      // straight should NOT vibrate
      await speaker.vibrate(InstructionKind.straight);
      expect(recordedPatterns, isEmpty);

      // turnLeft: two short pulses [0, 100, 100, 100]
      await speaker.vibrate(InstructionKind.turnLeft);
      expect(recordedPatterns.last, equals([0, 100, 100, 100]));

      // turnRight: one long pulse [0, 300]
      await speaker.vibrate(InstructionKind.turnRight);
      expect(recordedPatterns.last, equals([0, 300]));

      // arrive: three short pulses [0, 100, 100, 100, 100, 100]
      await speaker.vibrate(InstructionKind.arrive);
      expect(recordedPatterns.last, equals([0, 100, 100, 100, 100, 100]));

      // Verify sequence for a route with a left turn, a right turn, and arrival
      expect(recordedPatterns.length, 3);
    });
  });

  group('BUG 3 Regressions', () {
    testWidgets('tapping "I am here" mid-route advances along route to next waypoint and never resets to start', (tester) async {
      final wiring = Wiring.instance;
      wiring.currentPlaceId = 'entrance';

      // Route: entrance -> j1 (15 steps) -> cafe (10 steps)
      await tester.pumpWidget(const MaterialApp(
        home: NavigateScreen(destinationId: 'cafe'),
      ));
      await tester.pump();

      final tracker = wiring.tracker as RouteTracker;
      // Initially at entrance (legIndex 0, stepsAlong 0)
      expect(tracker.position.legIndex, 0);

      // Walk 5 steps
      for (int i = 0; i < 5; i++) {
        tracker.onStep(StepEvent(100 * (i + 1)));
      }
      expect(tracker.position.stepsAlong, 5);

      // Tap "I am here"
      final imHereButton = find.widgetWithText(ElevatedButton, 'I am here');
      expect(imHereButton, findsOneWidget);
      await tester.tap(imHereButton);
      await tester.pump();

      // Should advance to j1 (the node at the end of leg 0, i.e. legIndex 1 leaving j1), NOT reset to entrance!
      expect(tracker.position.legIndex, 1);
      expect(tracker.position.stepsAlong, 0);
      expect(tracker.position.anchoredBy, AnchorSource.tap);

      wiring.currentPlaceId = null;
    });
  });

  group('BUG 4 Regressions', () {
    test('short, clear wording built from Instruction.kind, steps and placeName', () {
      expect(
        AppSpeaker.formatSpeech(const Instruction(kind: InstructionKind.straight, steps: 10, text: 'Walk straight, about 10 steps.')),
        'Walk straight.',
      );
      expect(
        AppSpeaker.formatSpeech(const Instruction(kind: InstructionKind.turnLeft, steps: 5, text: 'In about 5 steps, turn left.')),
        'In 5 steps, turn left.',
      );
      expect(
        AppSpeaker.formatSpeech(const Instruction(kind: InstructionKind.turnLeft, steps: 2, text: 'Turn left now.')),
        'Turn left now.',
      );
      expect(
        AppSpeaker.formatSpeech(const Instruction(kind: InstructionKind.turnRight, steps: 7, text: 'In about 7 steps, turn right.')),
        'In 7 steps, turn right.',
      );
      expect(
        AppSpeaker.formatSpeech(const Instruction(kind: InstructionKind.turnRight, steps: 1, text: 'Turn right now.')),
        'Turn right now.',
      );
      expect(
        AppSpeaker.formatSpeech(const Instruction(kind: InstructionKind.arrive, placeName: 'Cafe', text: 'Cafe is here.')),
        'You have arrived at Cafe.',
      );
    });

    test('speech stops before speaking and does not speak on every step or repeat within 4s', () async {
      final events = <String>[];
      final spoken = <String>[];

      final speaker = AppSpeaker(
        customStop: () async {
          events.add('stop');
        },
        customSpeak: (text) async {
          events.add('speak:$text');
          spoken.add(text);
        },
      );

      // Step 1: straight
      await speaker.speak(const Instruction(kind: InstructionKind.straight, steps: 15, text: 'Walk straight, about 15 steps.'));
      expect(events, equals(['stop', 'speak:Walk straight.']));
      events.clear();

      // Step 2: same kind (straight countdown 14 steps) -> ignored!
      await speaker.speak(const Instruction(kind: InstructionKind.straight, steps: 14, text: 'Walk straight, about 14 steps.'));
      expect(events, isEmpty);

      // Step 3: same kind (straight countdown 13 steps) -> ignored!
      await speaker.speak(const Instruction(kind: InstructionKind.straight, steps: 13, text: 'Walk straight, about 13 steps.'));
      expect(events, isEmpty);

      // Change of kind: turnLeft prompt
      await speaker.speak(const Instruction(kind: InstructionKind.turnLeft, steps: 8, text: 'In about 8 steps, turn left.'));
      expect(events, equals(['stop', 'speak:In 8 steps, turn left.']));
      events.clear();

      // Turn now threshold
      await speaker.speak(const Instruction(kind: InstructionKind.turnLeft, steps: 2, text: 'Turn left now.'));
      expect(events, equals(['stop', 'speak:Turn left now.']));
      events.clear();

      // Immediate duplicate within 4s -> ignored
      await speaker.speak(const Instruction(kind: InstructionKind.turnLeft, steps: 2, text: 'Turn left now.'));
      expect(events, isEmpty);
    });
  });
}
