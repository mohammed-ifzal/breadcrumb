import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/app/screens/destination_list_screen.dart';
import 'package:breadcrumb/app/screens/home_screen.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/fakes.dart';

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
        throw StateError(
          'Cannot open model file /data/local/tmp/llm/gemma-4-E2B-it.litertlm',
        );
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

      // D30: the RAM read comes first, so the load starts a moment later.
      await Future<void>.delayed(Duration.zero);
      expect(loadCallCount, equals(1));

      completer.complete();
      final r1 = await f1;
      final r2 = await f2;

      expect(r1, isTrue);
      expect(r2, isTrue);
      expect(loadCallCount, equals(1));
      expect(wiring.aiStatus.value.isReady, isTrue);
      expect(wiring.isAiReady.value, isTrue);
      expect(wiring.aiStatus.value.tier, DeviceTier.full);
    });

    test(
      'D30: low RAM stays on the basic tier and never loads Gemma',
      () async {
        final wiring = Wiring.instance;
        final previous = wiring.sensingSource;
        addTearDown(() => wiring.sensingSource = previous);
        wiring.sensingSource = _LowRamSensing();
        var loads = 0;
        wiring.gemmaLoader = () async => loads++;

        expect(await wiring.warmAi(), isFalse);
        expect(loads, 0);
        expect(wiring.aiStatus.value.tier, DeviceTier.basic);
        expect(wiring.aiStatus.value.reason, '3000 MB RAM');
      },
    );

    testWidgets('UI shows Basic matching when warm throws or times out', (
      tester,
    ) async {
      final wiring = Wiring.instance;
      wiring.gemmaLoader = () async => throw Exception('Model file missing');

      await tester.pumpWidget(const MaterialApp(home: DestinationListScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Basic matching'), findsOneWidget);
      expect(find.text('model not loaded'), findsOneWidget);
      expect(find.text('AI warming...'), findsNothing);
    });

    testWidgets('HomeScreen shows Basic matching when status is unavailable', (
      tester,
    ) async {
      final wiring = Wiring.instance;
      wiring.gemmaLoader = () async => throw Exception('model failed');

      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Basic matching'), findsOneWidget);
      expect(find.text('model not loaded'), findsOneWidget);
    });
  });
}

class _LowRamSensing extends FakeSensingSource {
  @override
  Future<int> totalRamMb() async => 3000;
}
