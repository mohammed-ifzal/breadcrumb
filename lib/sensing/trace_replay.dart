import 'dart:convert';

/// Timestamped replay frames only; device info stays available as metadata.
class TraceReplayFrame {
  const TraceReplayFrame(this.record, this.tMs, this.delayMs);
  final Map<String, Object?> record;
  final int tMs;
  final int delayMs;
}

class TraceTiming {
  const TraceTiming(this.firstTimestampMs, this.lastTimestampMs);
  final int? firstTimestampMs, lastTimestampMs;
  int get durationMs =>
      firstTimestampMs == null ? 0 : lastTimestampMs! - firstTimestampMs!;
  double get durationSeconds => durationMs / 1000;
}

/// Pure-Dart JSONL reader shared by duration reporting and replay scheduling.
/// Full records retain info; neither its t nor meta t affects the sample clock.
class TraceReplayData {
  TraceReplayData._(this.records, this.timing);
  final List<Map<String, Object?>> records;
  final TraceTiming timing;

  factory TraceReplayData.fromRecords(Iterable<Map<String, Object?>> input) {
    final records = <Map<String, Object?>>[];
    int? first, last;
    for (final raw in input) {
      final record = Map<String, Object?>.unmodifiable(raw);
      records.add(record);
      final t = traceSampleTimeMs(record);
      if (t == null) continue;
      if (first == null || t < first) first = t;
      if (last == null || t > last) last = t;
    }
    if (records.isEmpty || records.first['type'] != 'meta') {
      throw const FormatException('First trace record must be meta');
    }
    return TraceReplayData._(
      List.unmodifiable(records),
      TraceTiming(first, last),
    );
  }

  factory TraceReplayData.parse(String jsonl) {
    final records = <Map<String, Object?>>[];
    var lineNumber = 0;
    for (final line in const LineSplitter().convert(jsonl)) {
      lineNumber++;
      if (line.trim().isEmpty) continue;
      try {
        records.add(Map<String, Object?>.from(jsonDecode(line) as Map));
      } catch (error) {
        throw FormatException('Invalid trace JSON at line $lineNumber: $error');
      }
    }
    return TraceReplayData.fromRecords(records);
  }

  /// Out-of-order hardware samples have zero delay and cannot move time back.
  Iterable<TraceReplayFrame> get frames sync* {
    int? clock;
    for (final record in records) {
      final t = traceSampleTimeMs(record);
      if (t == null) continue;
      final delay = clock == null || t <= clock ? 0 : t - clock;
      if (clock == null || t > clock) clock = t;
      yield TraceReplayFrame(record, t, delay);
    }
  }
}

/// Info timestamps describe stream/device metadata, NOT sensor measurement time.
int? traceSampleTimeMs(Map<String, Object?> record) {
  if (!const {
    'motion',
    'step',
    'gravity',
    'proximity',
    'light',
    'mark',
    'turn',
    'scan',
    'sign',
  }.contains(record['type'])) {
    return null;
  }
  final value = record['t'];
  if (value == null) return null;
  if (value is! num ||
      !value.isFinite ||
      value < 0 ||
      value != value.truncateToDouble()) {
    throw const FormatException('Invalid trace sample timestamp');
  }
  return value.toInt();
}
