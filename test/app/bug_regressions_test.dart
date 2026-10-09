import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/tracker.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/app/speaker.dart';
import 'package:breadcrumb/app/screens/destination_list_screen.dart';
import 'package:breadcrumb/app/screens/navigate_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
