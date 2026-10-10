import 'package:breadcrumb/sensing/trace_replay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cached device info does not turn a fifteen-second trace into fifteen minutes', () {
    final data = TraceReplayData.fromRecords([
      {'type': 'meta', 't': -999, 'map': 'spike'},
      {'type': 'info', 't': 2, 'totalRamMb': 15229},
      {'type': 'gravity', 't': 926467, 'x': 0, 'y': 0, 'z': 9.8},
      {'type': 'motion', 't': 941487, 'yawRate': 0, 'accel': 9.8},
      {'type': 'light', 't': 941496, 'lux': 18.15},
    ]);
    expect(data.timing.firstTimestampMs, 926467);
    expect(data.timing.lastTimestampMs, 941496);
    expect(data.timing.durationMs, 15029);
    expect(data.timing.durationSeconds, 15.029);
    expect(data.frames.map((e) => e.record['type']), [
      'gravity',
      'motion',
      'light',
    ]);
    expect(
      data.records.where((r) => r['type'] == 'info').single['totalRamMb'],
      15229,
    );
  });
  test('info between samples cannot reset or delay the playback clock', () {
    final data = TraceReplayData.fromRecords([
      {'type': 'meta'},
      {'type': 'motion', 't': 5000},
      {'type': 'info', 't': 0, 'totalRamMb': 8192},
      {'type': 'step', 't': 4980},
      {'type': 'light', 't': 5020},
      {'type': 'info', 't': 999999},
      {'type': 'motion', 't': 5040},
    ]);
    expect(data.frames.map((e) => e.delayMs), [0, 0, 20, 20]);
    expect(data.timing.durationMs, 60);
    expect(data.frames.map((e) => e.tMs), [5000, 4980, 5020, 5040]);
  });
  test('info-only and single-sample traces have zero duration', () {
    expect(
      TraceReplayData.fromRecords([
        {'type': 'meta'},
        {'type': 'info', 't': 100},
      ]).timing.durationMs,
      0,
    );
    expect(
      TraceReplayData.fromRecords([
        {'type': 'meta'},
        {'type': 'info', 't': 'not a sample'},
      ]).frames,
      isEmpty,
    );
    final one = TraceReplayData.fromRecords([
      {'type': 'meta'},
      {'type': 'step', 't': 100},
    ]);
    expect(one.timing.firstTimestampMs, 100);
    expect(one.timing.lastTimestampMs, 100);
    expect(one.timing.durationMs, 0);
  });
  test('JSONL replay keeps metadata and all far/near/far packets', () {
    final data = TraceReplayData.parse('''{"type":"meta"}
{"type":"info","t":0,"totalRamMb":8192}
{"type":"proximity","t":100,"cm":8,"maximumRange":8,"near":false}
{"type":"proximity","t":200,"cm":0,"maximumRange":8,"near":true}
{"type":"proximity","t":300,"cm":8,"maximumRange":8,"near":false}
''');
    expect(data.records, hasLength(5));
    expect(data.frames.map((f) => f.record['near']), [false, true, false]);
    expect(data.timing.durationMs, 200);
    expect(() => data.records.clear(), throwsUnsupportedError);
    expect(() => data.records.first['type'] = 'motion', throwsUnsupportedError);
  });
  test('malformed JSONL identifies its line and missing meta is rejected', () {
    expect(
      () => TraceReplayData.parse('{"type":"meta"}\ninvalid\n'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('line 2'),
        ),
      ),
    );
    expect(
      () => TraceReplayData.parse('{"type":"motion","t":0}\n'),
      throwsFormatException,
    );
    expect(() => TraceReplayData.parse(''), throwsFormatException);
    for (final t in [-1, 1.5, double.nan, 'bad']) {
      expect(
        () => TraceReplayData.fromRecords([
          {'type': 'meta'},
          {'type': 'step', 't': t},
        ]),
        throwsFormatException,
      );
    }
  });
}
