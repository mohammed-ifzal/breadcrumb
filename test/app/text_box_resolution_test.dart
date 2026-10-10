import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/app/screens/destination_list_screen.dart';
import 'package:breadcrumb/app/screens/navigate_screen.dart';
import 'package:breadcrumb/core/contracts.dart';

class DelayedStubResolver implements DestinationResolver {
  DelayedStubResolver({required this.delay, this.result});

  final Duration delay;
  final PlaceMatch? result;

  @override
  Future<PlaceMatch?> resolve(String utterance, MapGraph map) async {
    await Future<void>.delayed(delay);
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DestinationResolver originalResolver;

  setUp(() {
    originalResolver = Wiring.instance.destinationResolver;
    Wiring.instance.resetAiForTesting();
    Wiring.instance.map = Wiring.defaultDemoMap;
    Wiring.instance.currentPlaceId = 'entrance';
  });

  tearDown(() {
    Wiring.instance.destinationResolver = originalResolver;
    Wiring.instance.resetAiForTesting();
  });

  group('Part 2b: Text box resolution and fallback', () {
    testWidgets('exact place name resolves with the AI unavailable', (tester) async {
      final wiring = Wiring.instance;
      wiring.aiStatus.value = const AiStatus.unavailable('model not loaded');
      wiring.gemmaLoader = () async => throw Exception('Model missing');

      await tester.pumpWidget(const MaterialApp(home: DestinationListScreen()));
      await tester.pumpAndSettle();

      expect(find.text('AI unavailable'), findsOneWidget);

      // Enter exact place name 'Cafe'
      await tester.enterText(find.byType(TextField), 'Cafe');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
      await tester.pumpAndSettle();

      // Successfully navigates to NavigateScreen without AI
      expect(find.byType(NavigateScreen), findsOneWidget);
    });

    testWidgets('exact alias resolves with the AI unavailable', (tester) async {
      final wiring = Wiring.instance;
      wiring.aiStatus.value = const AiStatus.unavailable('model not loaded');
      wiring.gemmaLoader = () async => throw Exception('Model missing');

      await tester.pumpWidget(const MaterialApp(home: DestinationListScreen()));
      await tester.pumpAndSettle();

      // Enter alias 'coffee' (alias for cafe in demo map)
      await tester.enterText(find.byType(TextField), 'coffee');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
      await tester.pumpAndSettle();

      expect(find.byType(NavigateScreen), findsOneWidget);
    });

    testWidgets('unknown text with the AI unavailable shows the message immediately', (tester) async {
      final wiring = Wiring.instance;
      wiring.aiStatus.value = const AiStatus.unavailable('model not loaded');
      wiring.gemmaLoader = () async => throw Exception('Model missing');

      await tester.pumpWidget(const MaterialApp(home: DestinationListScreen()));
      await tester.pumpAndSettle();

      // Submit unknown place with AI unavailable
      await tester.enterText(find.byType(TextField), 'secret laboratory');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
      await tester.pump();

      // Immediately shows message without spinner
      expect(find.text("AI isn't ready. Pick from the list"), findsOneWidget);
      expect(find.text('Thinking...'), findsNothing);

      // Destination list remains visible and usable
      expect(find.text('Cafe'), findsOneWidget);
      expect(find.text('Stage Side'), findsOneWidget);
    });

    testWidgets('resolver timeout shows the message', (tester) async {
      final wiring = Wiring.instance;
      wiring.aiStatus.value = const AiStatus.ready();
      wiring.destinationResolveTimeout = const Duration(milliseconds: 50);
      wiring.destinationResolver = DelayedStubResolver(
        delay: const Duration(milliseconds: 300),
        result: const PlaceMatch('cafe', 0.5),
      );

      await tester.pumpWidget(const MaterialApp(home: DestinationListScreen()));
      await tester.pumpAndSettle();

      // Enter query requiring resolver
      await tester.enterText(find.byType(TextField), 'some non-exact query');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
      await tester.pump();

      // Initially thinking
      expect(find.text('Thinking...'), findsOneWidget);

      // Wait past timeout
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // Shows fallback message
      expect(find.text("Didn't catch that, pick from the list"), findsOneWidget);
      expect(find.text('Thinking...'), findsNothing);

      // List stays visible
      expect(find.text('Cafe'), findsOneWidget);
    });
  });
}
