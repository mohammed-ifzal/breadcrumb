import 'dart:convert';
import 'dart:io';

import 'package:breadcrumb/sensing/trace_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
        expect(rows[2], {'type': 'mark', 't': 30, 'note': 'turned left'});
        recorder.record({'type': 'step', 't': 40});
        await recorder.stop();
        expect(await file.readAsLines(), hasLength(3));
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
