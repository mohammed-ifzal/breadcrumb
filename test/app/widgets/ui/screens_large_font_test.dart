import 'dart:async';

import 'package:breadcrumb/app/screens/destination_list_screen.dart';
import 'package:breadcrumb/app/screens/home_screen.dart';
import 'package:breadcrumb/app/screens/navigate_screen.dart';
import 'package:breadcrumb/app/screens/record_screen.dart';
import 'package:breadcrumb/app/theme.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PendingResolver implements DestinationResolver {
  final Completer<PlaceMatch?> completer = Completer<PlaceMatch?>();

  @override
  Future<PlaceMatch?> resolve(String utterance, MapGraph map) => completer.future;
}

/// A small phone (360 x 740 dp) with the system font scale at 1.3.
Future<void> _pumpPhone(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(1080, 2220);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: BreadcrumbTheme.themeData,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
      child: child!,
    ),
    home: home,
  ));
}

void main() {
  late DestinationResolver originalResolver;

  setUp(() {
    originalResolver = Wiring.instance.destinationResolver;
    Wiring.instance.currentPlaceId = null;
  });

  tearDown(() {
    Wiring.instance.destinationResolver = originalResolver;
    Wiring.instance.currentPlaceId = null;
  });

  testWidgets('Home fits at font scale 1.3 and shows wordmark, tagline, cards and pills',
      (tester) async {
    await _pumpPhone(tester, const HomeScreen());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Find your way back. No GPS, no internet.'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('AI on-device'), findsOneWidget);
    expect(find.text('Navigate'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Record a trail'), 200);
    expect(find.text('Record a trail'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home "Record a trail" card opens the record screen', (tester) async {
    await _pumpPhone(tester, const HomeScreen());
    await tester.pump();

    await tester.scrollUntilVisible(find.text('Record a trail'), 200);
    await tester.tap(find.text('Record a trail'));
    await tester.pumpAndSettle();

    expect(find.byType(RecordScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Destination fits at font scale 1.3, idle and while thinking', (tester) async {
    final resolver = _PendingResolver();
    Wiring.instance.destinationResolver = resolver;

    await _pumpPhone(tester, const DestinationListScreen());
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Where do you want to go?'), findsWidgets);
    expect(find.text('MARKED PLACES'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'where can I get coffee');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
    await tester.pump();
    expect(find.text('Thinking...'), findsOneWidget);
    expect(find.text('On-device AI is matching your words to a marked place.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    resolver.completer.complete(null);
    await tester.pump();
    expect(find.text("Didn't catch that, pick from the list"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Navigate keeps SIMULATED visible under the app theme', (tester) async {
    Wiring.instance.currentPlaceId = 'entrance';
    await tester.pumpWidget(MaterialApp(
      theme: BreadcrumbTheme.themeData,
      home: const NavigateScreen(destinationId: 'cafe', simulate: true),
    ));
    await tester.pump();

    expect(find.text('SIMULATED'), findsWidgets);
    // Stop the simulation timer before the test ends.
    await tester.pumpWidget(const SizedBox());
  });
}
