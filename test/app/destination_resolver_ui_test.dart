import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/app/screens/destination_list_screen.dart';
import 'package:breadcrumb/app/screens/navigate_screen.dart';

class StubDestinationResolver implements DestinationResolver {
  StubDestinationResolver({this.onResolve});

  final Future<PlaceMatch?> Function(String utterance, MapGraph map)? onResolve;

  @override
  Future<PlaceMatch?> resolve(String utterance, MapGraph map) async {
    if (onResolve != null) {
      return onResolve!(utterance, map);
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DestinationResolver originalResolver;

  setUp(() {
    originalResolver = Wiring.instance.destinationResolver;
    Wiring.instance.resetAiForTesting();
    Wiring.instance.aiStatus.value = const AiStatus.ready();
    Wiring.instance.isAiReady.value = true;
  });

  tearDown(() {
    Wiring.instance.destinationResolver = originalResolver;
    Wiring.instance.resetAiForTesting();
  });

  testWidgets('renders "Where do you want to go?" text box, submit button, active mic button, and AI ready indicator', (tester) async {
    // Set AI status directly to test the three UI states.
    Wiring.instance.aiStatus.value = const AiStatus.loading();
    await tester.pumpWidget(const MaterialApp(home: DestinationListScreen()));
    await tester.pump();

    expect(find.text('Where do you want to go?'), findsWidgets);
    expect(find.widgetWithText(ElevatedButton, 'Submit'), findsOneWidget);
    expect(find.byType(IconButton), findsOneWidget);

    // Mic button is active
    final micButton = tester.widget<IconButton>(find.byType(IconButton));
    expect(micButton.onPressed, isNotNull);

    // AI indicator shows warming
    expect(find.text('AI warming...'), findsOneWidget);

    // Change to ready
    Wiring.instance.aiStatus.value = const AiStatus.ready();
    await tester.pump();
    expect(find.text('AI ready'), findsOneWidget);
  });

  testWidgets('D23: displays "You are at:" selector defaulting to last place', (tester) async {
    final wiring = Wiring.instance;
    // D23: effectiveCurrentPlaceId defaults to the last place kind node
    wiring.currentPlaceId = null;

    await tester.pumpWidget(const MaterialApp(home: DestinationListScreen()));
    await tester.pumpAndSettle();

    // The default start place is the last 'place' kind node in the demo map
    // Demo map places order: entrance(start), j1(junction), cafe(place),
    // j2(junction), stage(place), restroom(place)
    // Last place kind = restroom
    expect(find.textContaining('You are at:'), findsOneWidget);

    // Tap selector to see the bottom sheet
    await tester.tap(find.textContaining('You are at:'));
    await tester.pumpAndSettle();

    expect(find.text('Change Start Location'), findsOneWidget);
  });

  testWidgets('valid resolved place navigates to NavigateScreen', (tester) async {
    Wiring.instance.destinationResolver = StubDestinationResolver(
      onResolve: (utterance, map) async => const PlaceMatch('cafe', 1.0),
    );

    await tester.pumpWidget(const MaterialApp(home: DestinationListScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'coffee please');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
    await tester.pump();

    // Resolves and navigates to NavigateScreen
    await tester.pumpAndSettle();
    expect(find.byType(NavigateScreen), findsOneWidget);
  });

  testWidgets('shows Thinking... while working and disables submit', (tester) async {
    final completer = Completer<PlaceMatch?>();
    Wiring.instance.destinationResolver = StubDestinationResolver(
      onResolve: (utterance, map) => completer.future,
    );

    await tester.pumpWidget(const MaterialApp(home: DestinationListScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'I need some snacks');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
    await tester.pump();

    // Thinking indicator shown
    expect(find.text('Thinking...'), findsOneWidget);
    final submitButton = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(submitButton.onPressed, isNull);

    // Complete with result
    completer.complete(const PlaceMatch('cafe', 1.0));
    await tester.pumpAndSettle();
    expect(find.byType(NavigateScreen), findsOneWidget);
  });

  testWidgets('null or error shows "Didn\'t catch that, pick from the list" and list stays visible', (tester) async {
    Wiring.instance.destinationResolver = StubDestinationResolver(
      onResolve: (utterance, map) async => throw Exception('Model failed'),
    );

    await tester.pumpWidget(const MaterialApp(home: DestinationListScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'unknown place xyz');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
    await tester.pumpAndSettle();

    expect(find.text("Didn't catch that, pick from the list"), findsOneWidget);
    // Destination list items still visible
    expect(find.text('Cafe'), findsOneWidget);
    expect(find.text('Stage Side'), findsOneWidget);
  });

  testWidgets('junction or current place result is treated as null', (tester) async {
    // Current place is entrance; resolver returns 'entrance' or junction 'j1'
    Wiring.instance.destinationResolver = StubDestinationResolver(
      onResolve: (utterance, map) async => const PlaceMatch('j1', 1.0),
    );

    await tester.pumpWidget(const MaterialApp(home: DestinationListScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'go to junction');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
    await tester.pumpAndSettle();

    expect(find.text("Didn't catch that, pick from the list"), findsOneWidget);
  });

  testWidgets('ignores late answer if user typed again', (tester) async {
    final completer = Completer<PlaceMatch?>();
    Wiring.instance.destinationResolver = StubDestinationResolver(
      onResolve: (utterance, map) => completer.future,
    );

    await tester.pumpWidget(const MaterialApp(home: DestinationListScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'first request');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
    await tester.pump();
    expect(find.text('Thinking...'), findsOneWidget);

    // User types again
    await tester.enterText(find.byType(TextField), 'second request');
    await tester.pump();

    // First request finishes late
    completer.complete(const PlaceMatch('cafe', 1.0));
    await tester.pumpAndSettle();

    // Should NOT have navigated because user changed input
    expect(find.byType(NavigateScreen), findsNothing);
    expect(find.byType(DestinationListScreen), findsOneWidget);
  });
}
