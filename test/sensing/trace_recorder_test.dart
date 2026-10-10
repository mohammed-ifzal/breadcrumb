import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:breadcrumb/sensing/trace_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final failure in ['write', 'done', 'flush', 'close']) {
    test(
      '$failure failure logs once, stops recording and preserves path',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'breadcrumb-failure-',
        );
        final sink = FailingSink(failure);
        final logs = <String>[];
        final recorder = TraceRecorder(
          documentsDirectory: () async => directory,
          openSink: (_) => sink,
          logger: logs.add,
        );
        try {
          await recorder.start({'walker': 'T2', 'map': 'loop'});
          final path = recorder.state.value.path;
          expect(path, endsWith('.jsonl'));
          if (failure == 'done') sink.fail();
          recorder.record({'type': 'step', 't': 20});
          await Future<void>.delayed(Duration.zero);
          await recorder.stop();
          recorder.record({'type': 'step', 't': 40});
          recorder.mark(60, 'after failure');
          await recorder.stop();
          expect(logs, hasLength(1));
          expect(recorder.state.value.recording, isFalse);
          expect(recorder.state.value.path, path);
          expect(recorder.state.value.error, contains('disk full'));
          expect(sink.closes, 1);
        } finally {
          await recorder.stop();
          await directory.delete(recursive: true);
        }
      },
    );
  }
  test(
    'trace writes meta first, raw samples and marks, flushes on stop',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'breadcrumb-trace-',
      );
      final recorder = TraceRecorder(documentsDirectory: () async => directory);
      try {
        await recorder.start({
          'map': 'table_loop',
          'walker': 'T2',
          'from': 'p0',
          'to': 'p2',
          'stepSource': 'detector',
        });
        recorder.record({
          'type': 'motion',
          't': 20,
          'yawRate': 90.0,
          'accel': 9.8,
        });
        recorder.record({
          'type': 'gravity',
          't': 21,
          'x': 0,
          'y': 0,
          'z': 9.8,
          'source': 'sensor',
        });
        recorder.record({
          'type': 'proximity',
          't': 22,
          'near': true,
          'cm': 0.0,
        });
        recorder.record({'type': 'light', 't': 23, 'lux': 12.5});
        recorder.record({'type': 'info', 't': 24, 'totalRamMb': 8192});
        recorder.mark(30, 'turned left');
        await recorder.stop();
        final file = directory
            .listSync(recursive: true)
            .whereType<File>()
            .single;
        expect(
          file.parent.path,
          '${directory.path}${Platform.pathSeparator}traces',
        );
        expect(file.path, endsWith('.jsonl'));
        final rows = (await file.readAsLines())
            .map((line) => jsonDecode(line))
            .toList();
        expect(rows[0]['type'], 'meta');
        expect(rows[0]['walker'], 'T2');
        expect(rows[1]['yawRate'], 90);
        expect(rows[2], {
          'type': 'gravity',
          't': 21,
          'x': 0,
          'y': 0,
          'z': 9.8,
          'source': 'sensor',
        });
        expect(rows[3], {
          'type': 'proximity',
          't': 22,
          'near': true,
          'cm': 0.0,
        });
        expect(rows[4], {'type': 'light', 't': 23, 'lux': 12.5});
        expect(rows[5], {'type': 'info', 't': 24, 'totalRamMb': 8192});
        expect(rows[6], {'type': 'mark', 't': 30, 'note': 'turned left'});
        recorder.record({'type': 'step', 't': 40});
        await recorder.stop();
        expect(await file.readAsLines(), hasLength(7));
      } finally {
        await recorder.stop();
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'starting twice is rejected without replacing an active trace',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'breadcrumb-trace-',
      );
      final recorder = TraceRecorder(documentsDirectory: () async => directory);
      try {
        await recorder.start({'walker': 'T2', 'map': 'loop'});
        await expectLater(recorder.start({'walker': 'T2'}), throwsStateError);
      } finally {
        await recorder.stop();
        await directory.delete(recursive: true);
      }
    },
  );
}

class FailingSink implements IOSink {
  FailingSink(this.failure);
  final String failure;
  final completion = Completer<void>();
  var writes = 0;
  var closes = 0;
  void fail() {
    if (!completion.isCompleted) {
      completion.completeError(const FileSystemException('disk full'));
    }
  }

  @override
  Future<void> get done => completion.future;
  @override
  void writeln([Object? object = '']) {
    writes++;
    if (failure == 'write' && writes > 1) {
      throw const FileSystemException('disk full');
    }
  }

  @override
  Future<void> flush() async {
    if (failure == 'flush') {
      throw const FileSystemException('disk full');
    }
  }

  @override
  Future<void> close() async {
    closes++;
    if (!completion.isCompleted) completion.complete();
    if (failure == 'close' || failure == 'write' || failure == 'done') {
      throw const FileSystemException('disk full');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
