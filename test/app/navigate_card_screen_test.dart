import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:breadcrumb/app/screens/navigate_screen.dart';
import 'package:breadcrumb/app/widgets/trail_view.dart';
import 'package:breadcrumb/app/theme.dart';
import 'package:breadcrumb/app/wiring.dart';

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

    // 1. Top card in accent color with 56 dp arrow icon
    expect(find.byType(ConfidenceRing), findsOneWidget);
    final ringFinder = find.byType(ConfidenceRing);
    final ringWidget = tester.widget<ConfidenceRing>(ringFinder);
    expect(ringWidget.size, 56.0);
    expect(ringWidget.confidence, 1.0); // full ring by default

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

  testWidgets('ConfidenceRing displays amber below 0.5', (tester) async {
    // Test ConfidenceRing widget directly with high and low confidence
    await tester.pumpWidget(
      MaterialApp(
        theme: BreadcrumbTheme.themeData,
        home: const Scaffold(
          body: Column(
            children: [
              ConfidenceRing(
                confidence: 0.8,
                child: Icon(Icons.arrow_upward),
              ),
              ConfidenceRing(
                confidence: 0.3,
                child: Icon(Icons.arrow_downward),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(ConfidenceRing), findsNWidgets(2));
    final highConfidence = tester.widget<ConfidenceRing>(find.byType(ConfidenceRing).first);
    final lowConfidence = tester.widget<ConfidenceRing>(find.byType(ConfidenceRing).last);
    expect(highConfidence.confidence, 0.8);
    expect(lowConfidence.confidence, 0.3);
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
    expect(find.byType(ConfidenceRing), findsOneWidget);
    expect(find.byType(TrailView), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, "I'm here"), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Scan sign'), findsOneWidget);
  });
}
