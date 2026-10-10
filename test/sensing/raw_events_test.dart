import 'package:breadcrumb/sensing/raw_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gravity parses numeric vector and round-trips source and units', () {
    final raw = <String, Object?>{
      'type': 'gravity',
      't': 20.0,
      'x': 1,
      'y': -2.5,
      'z': 9.8,
      'source': 'accelerometer',
    };
    final sample = RawSensingEvent.fromJson(raw) as GravitySample;
    expect(
      (sample.t, sample.x, sample.y, sample.z, sample.source),
      (20, 1.0, -2.5, 9.8, 'accelerometer'),
    );
    expect(sample.toJson(), raw);
  });
  test(
    'proximity retains native near/far and raw centimetres without a threshold',
    () {
      for (final near in [true, false]) {
        final raw = <String, Object?>{
          'type': 'proximity',
          't': 50,
          'near': near,
          'cm': 3.5,
        };
        final sample = RawSensingEvent.fromJson(raw) as ProximitySample;
        expect(sample.near, near);
        expect(sample.cm, 3.5);
        expect(sample.toJson(), raw);
      }
    },
  );
  test('ambient light preserves zero and fractional lux', () {
    for (final lux in [0, 12.5]) {
      final raw = <String, Object?>{'type': 'light', 't': 200, 'lux': lux};
      final sample = RawSensingEvent.fromJson(raw) as LightSample;
      expect(sample.lux, lux);
      expect(sample.toJson(), raw);
    }
  });
  test('partial device info keeps missing capability fields unknown', () {
    final raw = <String, Object?>{'type': 'info', 't': 0, 'totalRamMb': 8192.0};
    final info = RawSensingEvent.fromJson(raw) as DeviceInfo;
    expect(info.totalRamMb, 8192);
    expect(info.proximityAvailable, isNull);
    expect(info.lightAvailable, isNull);
    expect(info.gravityAvailable, isNull);
    expect(info.toJson(), raw);
  });
  test(
    'device info preserves independent availability and fallback provenance',
    () {
      final raw = <String, Object?>{
        'type': 'info',
        'gravityAvailable': false,
        'gravitySource': 'accelerometer',
        'gravityLowPassEnabled': true,
        'proximityAvailable': false,
        'lightAvailable': true,
        'totalRamAvailable': false,
      };
      final info = RawSensingEvent.fromJson(raw) as DeviceInfo;
      expect(info.gravitySource, 'accelerometer');
      expect(info.gravityLowPassEnabled, isTrue);
      expect(info.toJson(), raw);
    },
  );
  test('invalid raw numbers and flags are rejected with FormatException', () {
    for (final raw in <Map<String, Object?>>[
      {'type': 'gravity', 't': -1, 'x': 0, 'y': 0, 'z': 9.8},
      {'type': 'gravity', 't': 1.5, 'x': 0, 'y': 0, 'z': 9.8},
      {'type': 'gravity', 't': 0, 'x': double.nan, 'y': 0, 'z': 9.8},
      {'type': 'proximity', 't': 0, 'near': 'yes', 'cm': 0},
      {'type': 'proximity', 't': 0, 'near': false, 'cm': -1},
      {'type': 'light', 't': 0, 'lux': double.infinity},
      {'type': 'light', 't': 0, 'lux': -1},
      {'type': 'info', 'totalRamMb': -1},
      {'type': 'info', 'lightAvailable': 0},
      {'type': 'unexpected'},
    ]) {
      expect(() => RawSensingEvent.fromJson(raw), throwsFormatException);
    }
  });
  test(
    'proximity parses far, near and back to far using arbitrary sensor range',
    () {
      final packets = <Map<String, Object?>>[
        {
          'type': 'proximity',
          't': 0,
          'near': false,
          'cm': 8.0,
          'maximumRange': 8.0,
          'origin': 'assumed',
        },
        {
          'type': 'proximity',
          't': 8800,
          'near': true,
          'cm': 0.0,
          'maximumRange': 8.0,
          'origin': 'sensor',
        },
        {
          'type': 'proximity',
          't': 14000,
          'near': false,
          'cm': 8.0,
          'maximumRange': 8.0,
          'origin': 'sensor',
        },
      ];
      final samples = packets
          .map((raw) => RawSensingEvent.fromJson(raw) as ProximitySample)
          .toList();
      expect(samples.map((e) => e.near), [false, true, false]);
      expect(samples.map((e) => e.cm), [8.0, 0.0, 8.0]);
      expect(samples.map((e) => e.maximumRange), everyElement(8.0));
      expect(samples.map((e) => e.toJson()).toList(), packets);
    },
  );
  test(
    'proximity snapshots preserve origin without changing legacy packets',
    () {
      final sample = RawSensingEvent.fromJson({
        'type': 'proximity',
        't': 926467,
        'near': false,
        'cm': 12,
        'maximumRange': 12,
        'origin': 'cached',
        'snapshot': true,
      }) as ProximitySample;
      expect(sample.snapshot, isTrue);
      expect(sample.origin, 'cached');
      expect(sample.maximumRange, 12);
      expect(sample.toJson()['snapshot'], isTrue);
      final legacy = RawSensingEvent.fromJson({
        'type': 'proximity',
        't': 0,
        'near': false,
        'cm': 5,
      }) as ProximitySample;
      expect(legacy.maximumRange, isNull);
      expect(legacy.origin, isNull);
      expect(legacy.toJson(), {
        'type': 'proximity',
        't': 0,
        'near': false,
        'cm': 5.0,
      });
    },
  );
  test('invalid proximity ranges and origins are rejected', () {
    for (final extra in <Map<String, Object?>>[
      {'maximumRange': 0},
      {'maximumRange': -1},
      {'maximumRange': double.nan},
      {'origin': 'guessed'},
      {'snapshot': 'yes'},
    ]) {
      expect(
        () => RawSensingEvent.fromJson({
          'type': 'proximity',
          't': 0,
          'near': false,
          'cm': 8,
          ...extra,
        }),
        throwsFormatException,
      );
    }
  });
}
