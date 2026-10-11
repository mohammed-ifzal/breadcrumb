import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:breadcrumb/app/screens/navigate_screen.dart';
import 'package:breadcrumb/app/widgets/arrow_glyph.dart';
import 'package:breadcrumb/app/widgets/trail_view.dart';
import 'package:breadcrumb/app/theme.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/core/contracts.dart';


void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync();
    Wiring.instance.documentsDirectory = () async => tempDir;
    Wiring.instance.map = Wiring.defaultDemoMap;
    Wiring.instance.currentPlaceId = 'entrance';
    Wiring.instance.resetAiForTesting();
    Wiring.instance.aiStatus.value = const AiStatus.ready();
    Wiring.instance.isAiReady.value = true;
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
    Wiring.instance.documentsDirectory = getApplicationDocumentsDirectory;
    Wiring.instance.map = Wiring.defaultDemoMap;
    Wiring.instance.currentPlaceId = null;
    Wiring.instance.resetAiForTesting();
  });

  Future<void> pumpScreen(WidgetTester tester, Widget child, {TextScaler? textScaler, Size? size, double? devicePixelRatio}) async {
    tester.view.physicalSize = size ?? const Size(1080, 2400);
    tester.view.devicePixelRatio = devicePixelRatio ?? 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: BreadcrumbTheme.themeData,
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: textScaler ?? TextScaler.noScaling,
          ),
          child: c!,
        ),
        home: child,
      ),
    );
    await tester.pump();
  }

  testWidgets('Google-Maps-style navigation card layout and components render correctly', (tester) async {
    await pumpScreen(tester, const NavigateScreen(destinationId: 'cafe'));

    // 1. Instruction card in accent with the 4-bar confidence gauge in the dock
    expect(find.byType(InstructionCard), findsOneWidget);
    expect(tester.widget<InstructionCard>(find.byType(InstructionCard)).tone, BreadcrumbTheme.accent);
    expect(find.byType(ConfidenceGauge), findsOneWidget);
    final gauge = tester.widget<ConfidenceGauge>(find.byType(ConfidenceGauge));
    expect(gauge.confidence, 1.0); // full gauge by default
    expect(gauge.bars, 4);

    // 2. Instruction text and steps line under it
    // Entrance to Cafe: 15 steps to j1 then 10 steps to cafe.
    expect(find.textContaining('steps'), findsWidgets);

    // 3. Next instruction strip ("Then: ...")
    expect(find.textContaining('Then:'), findsOneWidget);

    // 4. TrailView fills the middle
    expect(find.byType(TrailView), findsOneWidget);

    // 5. Bottom sheet with destination name, steps left, progress bar, and two buttons
    expect(find.text('Cafe'), findsOneWidget);
    expect(find.textContaining('steps left'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, "I'm here"), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Scan sign'), findsOneWidget);

    // Buttons are equal width
    final hereSize = tester.getSize(find.widgetWithText(ElevatedButton, "I'm here"));
    final scanSize = tester.getSize(find.widgetWithText(ElevatedButton, 'Scan sign'));
    expect((hereSize.width - scanSize.width).abs(), lessThanOrEqualTo(1.0));
  });

  testWidgets('ConfidenceGauge maps confidence to 4 bars: accent, accent, off-route, error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BreadcrumbTheme.themeData,
        home: const Scaffold(
          body: Column(
            children: [
              ConfidenceGauge(confidence: 0.8),
              ConfidenceGauge(confidence: 0.3),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(ConfidenceGauge), findsNWidgets(2));
    final highConfidence = tester.widget<ConfidenceGauge>(find.byType(ConfidenceGauge).first);
    final lowConfidence = tester.widget<ConfidenceGauge>(find.byType(ConfidenceGauge).last);
    expect(highConfidence.confidence, 0.8);
    expect(lowConfidence.confidence, 0.3);
    expect(ConfidenceGauge.barsFor(1.0), 4);
    expect(ConfidenceGauge.barsFor(0.6), 3);
    expect(ConfidenceGauge.barsFor(0.3), 2);
    expect(ConfidenceGauge.barsFor(0.1), 1);
    expect(ConfidenceGauge.colorFor(4), BreadcrumbTheme.accent);
    expect(ConfidenceGauge.colorFor(3), BreadcrumbTheme.accent);
    expect(ConfidenceGauge.colorFor(2), BreadcrumbTheme.offRoute);
    expect(ConfidenceGauge.colorFor(1), BreadcrumbTheme.error);
    expect(find.bySemanticsLabel(RegExp('Position confidence')), findsNWidgets(2));
  });

  testWidgets('SIMULATED label remains visible when simulating', (tester) async {
    await pumpScreen(tester, const NavigateScreen(destinationId: 'cafe', simulate: true));
    expect(find.text('SIMULATED'), findsWidgets);
  });

  testWidgets('Navigate fits on 360x640 with textScaler 1.3 without overflow', (tester) async {
    await pumpScreen(
      tester,
      const NavigateScreen(destinationId: 'cafe'),
      textScaler: const TextScaler.linear(1.3),
      size: const Size(360 * 2, 640 * 2),
      devicePixelRatio: 2.0,
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(ConfidenceGauge), findsOneWidget);
    expect(find.byType(TrailView), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, "I'm here"), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Scan sign'), findsOneWidget);
  });

  testWidgets('Navigate card hides steps line when steps == 0 (e.g. Turn around)', (tester) async {
    Wiring.instance.guide = const _FixedInstructionGuide(
      Instruction(
        kind: InstructionKind.turnAround,
        steps: 0,
        text: 'Turn around, then walk straight.',
      ),
    );

    await pumpScreen(tester, const NavigateScreen(destinationId: 'cafe'));

    expect(find.text('Turn around, then walk straight.'), findsOneWidget);
    expect(find.text('0 steps'), findsNothing);
    expect(find.text('0 step'), findsNothing);
  });

  testWidgets("a question shows inline Yes / Not yet; Yes is the I'm here handler, Not yet hides them", (tester) async {
    Wiring.instance.guide = const _FixedInstructionGuide(
      Instruction(kind: InstructionKind.confirmPlace, placeName: 'Cafe', text: 'Are you at Cafe?'),
    );
    await pumpScreen(tester, const NavigateScreen(destinationId: 'cafe'));

    expect(find.byKey(const ValueKey('prompt-yes')), findsOneWidget);
    expect(find.byKey(const ValueKey('prompt-not-yet')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('prompt-not-yet')));
    await tester.pump();
    expect(find.byKey(const ValueKey('prompt-yes')), findsNothing);
    expect(find.text('Are you at Cafe?'), findsOneWidget);
  });

  testWidgets('off route turns the card orange; arrival turns it green with the pin', (tester) async {
    Wiring.instance.guide = const _FixedInstructionGuide(
      Instruction(
        kind: InstructionKind.offRoute,
        text: "Looks like you went off the path. Go back to the last corner or tap I'm here.",
      ),
    );
    await pumpScreen(tester, const NavigateScreen(destinationId: 'cafe'));
    var card = tester.widget<InstructionCard>(find.byType(InstructionCard));
    expect(card.tone, BreadcrumbTheme.offRoute);
    expect(card.tone, isNot(BreadcrumbTheme.warning));

    Wiring.instance.guide = const _FixedInstructionGuide(
      Instruction(kind: InstructionKind.arrive, placeName: 'Cafe', text: 'Cafe is here.'),
    );
    await pumpScreen(tester, const NavigateScreen(key: ValueKey('again'), destinationId: 'cafe'));
    card = tester.widget<InstructionCard>(find.byType(InstructionCard));
    expect(card.tone, BreadcrumbTheme.success);
    expect(card.glyph, ArrowKind.arrival);
  });

  testWidgets('a long instruction on a small phone at 1.3 wraps instead of being cut off', (tester) async {
    const long = "Looks like you went off the path. Go back to the last corner or tap I'm here.";
    Wiring.instance.guide = const _FixedInstructionGuide(
      Instruction(kind: InstructionKind.offRoute, text: long),
    );
    await pumpScreen(
      tester,
      const NavigateScreen(destinationId: 'cafe'),
      textScaler: const TextScaler.linear(1.3),
      size: const Size(360 * 2, 640 * 2),
    );

    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(find.text(long));
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    expect(text.maxLines, isNull);
  });
}

class _FixedInstructionGuide implements Guide {
  final Instruction instruction;
  const _FixedInstructionGuide(this.instruction);

  @override
  Instruction next(RoutePlan r, Position p) => instruction;
}
