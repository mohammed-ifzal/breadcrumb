import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/app/screens/destination_list_screen.dart';
import 'package:breadcrumb/app/screens/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Wiring.instance.resetAiForTesting();
  });

  tearDown(() {
    Wiring.instance.resetAiForTesting();
  });

  group('Part 2a: AI Status and warmAi', () {
    test('warm times out -> unavailable', () async {
      final wiring = Wiring.instance;
      // Inject loader that never completes
      wiring.gemmaLoader = () => Completer<void>().future;
      wiring.aiWarmTimeout = const Duration(milliseconds: 20);

      final result = await wiring.warmAi();
      expect(result, isFalse);
      expect(wiring.aiStatus.value.isUnavailable, isTrue);
      expect(wiring.aiStatus.value.reason, 'model not loaded');
      expect(wiring.isAiReady.value, isFalse);
    });

    test('warm throws -> unavailable', () async {
      final wiring = Wiring.instance;
      wiring.gemmaLoader = () async {
        throw StateError('Cannot open model file /data/local/tmp/llm/gemma-4-E2B-it.litertlm');
      };

      final result = await wiring.warmAi();
      expect(result, isFalse);
      expect(wiring.aiStatus.value.isUnavailable, isTrue);
      expect(wiring.aiStatus.value.reason, 'model not loaded');
      expect(wiring.isAiReady.value, isFalse);
    });

    test('two concurrent warm calls start one load', () async {
      final wiring = Wiring.instance;
      var loadCallCount = 0;
      final completer = Completer<void>();

      wiring.gemmaLoader = () async {
        loadCallCount++;
        await completer.future;
      };

      // Call warmAi twice concurrently
      final f1 = wiring.warmAi();
      final f2 = wiring.warmAi();

      expect(loadCallCount, equals(1));

      completer.complete();
      final r1 = await f1;
      final r2 = await f2;

      expect(r1, isTrue);
      expect(r2, isTrue);
      expect(loadCallCount, equals(1));
      expect(wiring.aiStatus.value.isReady, isTrue);
      expect(wiring.isAiReady.value, isTrue);
    });

    testWidgets('UI shows AI unavailable when warm throws or times out', (tester) async {
      final wiring = Wiring.instance;
      wiring.gemmaLoader = () async => throw Exception('Model file missing');

      await tester.pumpWidget(const MaterialApp(home: DestinationListScreen()));
      await tester.pumpAndSettle();

      expect(find.text('AI unavailable'), findsOneWidget);
      expect(find.text('model not loaded'), findsOneWidget);
      expect(find.text('AI warming...'), findsNothing);
    });

    testWidgets('HomeScreen shows AI unavailable when status is unavailable', (tester) async {
      final wiring = Wiring.instance;
      wiring.gemmaLoader = () async => throw Exception('model failed');

      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();

      expect(find.text('AI unavailable'), findsOneWidget);
      expect(find.text('model not loaded'), findsOneWidget);
    });
  });
}
