import 'dart:async';

import 'package:breadcrumb/ai/destination_resolver.dart';
import 'package:breadcrumb/ai/device_tier.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/fakes.dart';
import 'package:breadcrumb/core/place_matcher.dart';
import 'package:breadcrumb/core/tuning.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/test_maps.dart';

/// Always picks [answer]; counts how often it was asked.
class CountingChooser implements PlaceChooser {
  CountingChooser(this.answer);

  final String? answer;
  var asked = 0;

  @override
  Future<String?> choosePlace(String utterance, List<Place> places) async {
    asked++;
    return answer;
  }
}

void main() {
  group('ramAllowsGemma', () {
    test('at or above fullTierMinRamMb', () {
      expect(ramAllowsGemma(fullTierMinRamMb), isTrue);
      expect(ramAllowsGemma(12000), isTrue);
      expect(ramAllowsGemma(fullTierMinRamMb - 1), isFalse);
      expect(ramAllowsGemma(4000), isFalse);
    });

    test('unknown RAM (0) lets loading decide', () {
      expect(ramAllowsGemma(0), isTrue);
    });
  });

  group('AiTierGate', () {
    AiTierGate gate(int ram, {Object? loadError, bool hang = false, List<int>? loads}) =>
        AiTierGate(
          totalRamMb: () async => ram,
          loadGemma: () async {
            loads?.add(1);
            if (hang) await Completer<void>().future;
            if (loadError != null) throw loadError;
          },
          loadTimeout: const Duration(milliseconds: 20),
        );

    test('enough RAM and Gemma loads: full', () async {
      final g = gate(12000);
      expect(await g.decide(), DeviceTier.full);
      expect(g.tier, DeviceTier.full);
      expect(g.reason, isNull);
      expect(g.ramMb, 12000);
    });

    test('low RAM: basic, and Gemma is never loaded', () async {
      final loads = <int>[];
      final g = gate(4000, loads: loads);
      expect(await g.decide(), DeviceTier.basic);
      expect(loads, isEmpty);
      expect(g.reason, contains('4000 MB'));
    });

    test('enough RAM but the load throws: basic', () async {
      final g = gate(12000, loadError: StateError('no model file'));
      expect(await g.decide(), DeviceTier.basic);
      expect(g.reason, contains('no model file'));
    });

    test('enough RAM but the load times out: basic', () async {
      expect(await gate(12000, hang: true).decide(), DeviceTier.basic);
    });

    test('unknown RAM: the load decides', () async {
      expect(await gate(0).decide(), DeviceTier.full);
      expect(await gate(0, loadError: 'x').decide(), DeviceTier.basic);
    });

    test('a RAM read that throws counts as unknown', () async {
      final g = AiTierGate(
        totalRamMb: () async => throw StateError('no channel'),
        loadGemma: () async {},
      );
      expect(await g.decide(), DeviceTier.full);
      expect(g.ramMb, 0);
    });

    test('decides once: concurrent and later calls share it', () async {
      final loads = <int>[];
      final g = gate(12000, loads: loads);
      final both = await Future.wait([g.decide(), g.decide()]);
      await g.decide();
      expect(both, [DeviceTier.full, DeviceTier.full]);
      expect(loads, hasLength(1));
    });

    test('tier is null before deciding', () {
      expect(gate(12000).tier, isNull);
    });

    test('works with FakeSensingSource RAM (12 GB)', () async {
      final g = AiTierGate(
        totalRamMb: FakeSensingSource().totalRamMb,
        loadGemma: () async {},
      );
      expect(await g.decide(), DeviceTier.full);
    });
  });

  group('aiChipLabel', () {
    test('basic says Basic matching', () {
      expect(aiChipLabel(DeviceTier.basic), 'Basic matching');
      expect(aiChipLabel(DeviceTier.full), 'AI on-device');
    });
  });

  group('destinationResolverFor', () {
    test('basic never asks Gemma, even with a chooser', () async {
      final chooser = CountingChooser('stage_side');
      final r = destinationResolverFor(
        DeviceTier.basic,
        matcher: FuzzyPlaceMatcher(),
        chooser: chooser,
      );
      expect(r, isA<BasicDestinationResolver>());
      expect(await r.resolve('take me to the moon', demoMap), isNull);
      expect(chooser.asked, 0);
    });

    test('basic matches names and aliases', () async {
      final r = destinationResolverFor(DeviceTier.basic, matcher: FuzzyPlaceMatcher());
      expect((await r.resolve('stage side', demoMap))?.placeId, 'stage_side');
      expect((await r.resolve('where is the canteen', demoMap))?.placeId, 'food_counter');
      expect(await r.resolve('   ', demoMap), isNull);
    });

    test('full with a chooser falls back to Gemma', () async {
      final chooser = CountingChooser('stage_side');
      final r = destinationResolverFor(
        DeviceTier.full,
        matcher: FuzzyPlaceMatcher(),
        chooser: chooser,
      );
      expect(r, isA<GemmaDestinationResolver>());
      expect((await r.resolve('where is the show', demoMap))?.placeId, 'stage_side');
      expect(chooser.asked, 1);
    });

    test('full without a chooser is basic', () {
      expect(
        destinationResolverFor(DeviceTier.full, matcher: FuzzyPlaceMatcher()),
        isA<BasicDestinationResolver>(),
      );
    });
  });
}
