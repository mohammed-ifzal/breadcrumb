import 'package:breadcrumb/app/screens/destination_list_screen.dart';
import 'package:breadcrumb/app/screens/navigate_screen.dart';
import 'package:breadcrumb/app/theme.dart';
import 'package:breadcrumb/app/widgets/ui/ui.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    Wiring.instance.resetAiForTesting();
    Wiring.instance.map = Wiring.defaultDemoMap;
    Wiring.instance.currentPlaceId = 'entrance';
    Wiring.instance.aiStatus.value = const AiStatus.ready();
    Wiring.instance.isAiReady.value = true;
  });

  tearDown(() {
    Wiring.instance.resetAiForTesting();
    Wiring.instance.currentPlaceId = null;
  });

  testWidgets('a match leaves an "Understood" card with the request and the place, no percentage', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: BreadcrumbTheme.themeData, home: const DestinationListScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Cafe');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigateScreen), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    final card = find.textContaining('Understood: "Cafe"', findRichText: true);
    expect(card, findsOneWidget);
    expect(find.textContaining('%', findRichText: true), findsNothing);
    // One-floor map: no floor tag.
    expect(find.textContaining('(Floor', findRichText: true), findsNothing);

    // Typing again clears it.
    await tester.enterText(find.byType(TextField), 'Sta');
    await tester.pump();
    expect(card, findsNothing);
  });

  testWidgets('the AI pill shows a coloured dot for the real state', (tester) async {
    Wiring.instance.aiStatus.value = const AiStatus.loading();
    await tester.pumpWidget(MaterialApp(theme: BreadcrumbTheme.themeData, home: const DestinationListScreen()));
    await tester.pump();
    var pill = tester.widget<StatusPill>(find.byType(StatusPill));
    expect(pill.label, 'AI warming up…');
    expect(pill.dotColor, BreadcrumbTheme.textSecondary);

    Wiring.instance.aiStatus.value = const AiStatus.ready();
    await tester.pump();
    pill = tester.widget<StatusPill>(find.byType(StatusPill));
    expect(pill.label, 'On-device AI ready');
    expect(pill.dotColor, BreadcrumbTheme.accent);

    Wiring.instance.aiStatus.value = const AiStatus.unavailable('model not loaded');
    await tester.pump();
    pill = tester.widget<StatusPill>(find.byType(StatusPill));
    expect(pill.label, 'Basic matching');
    expect(find.text('model not loaded'), findsOneWidget);
  });
}
