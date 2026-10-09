import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// App-private JSONL traces. Callers must await start before feeding events.
class TraceRecorder {
  TraceRecorder({Future<Directory> Function()? documentsDirectory})
    : _documentsDirectory =
          documentsDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectory;
  IOSink? _sink;
  Future<void>? _opening;
  Object? _writeError;

  Future<void> start(Map<String, Object?> meta) {
    if (_sink != null || _opening != null) {
      return Future.error(StateError('A trace is already active.'));
    }
    final snapshot = Map<String, Object?>.of(meta);
    final opening = _open(snapshot).whenComplete(() => _opening = null);
    _opening = opening;
    return opening;
  }

  Future<void> _open(Map<String, Object?> meta) async {
    // Serialize before opening a file so invalid metadata leaves no empty trace.
    final firstLine = jsonEncode({...meta, 'type': 'meta'});
    final documents = await _documentsDirectory();
    final directory = Directory(
      '${documents.path}${Platform.pathSeparator}traces',
    );
    await directory.create(recursive: true);
    String slug(Object? value) => (value?.toString() ?? 'unknown').replaceAll(
      RegExp('[^a-zA-Z0-9_-]'),
      '_',
    );
    final now = DateTime.now().toUtc();
    final date = now.toIso8601String().substring(0, 10);
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      '$date-${slug(meta['walker'])}-${slug(meta['map'])}-${now.microsecondsSinceEpoch}.jsonl',
    );
    await file.create(exclusive: true);
    _writeError = null;
    final sink = file.openWrite();
    _sink = sink;
    // Attach immediately so filesystem failures are observed rather than becoming
    // uncaught asynchronous errors; stop propagates them to the caller.
    sink.done.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        _writeError = error;
      },
    );
    sink.writeln(firstLine);
  }

  void record(Map<String, Object?> event) {
    final sink = _sink;
    if (sink == null) return;
    if (_writeError != null) {
      throw FileSystemException('Trace write failed: $_writeError');
    }
    sink.writeln(jsonEncode(event));
  }

  void mark(int t, String note) =>
      record({'type': 'mark', 't': t, 'note': note});

  Future<void> stop() async {
    await _opening;
    final sink = _sink;
    _sink = null;
    if (sink == null) return;
    try {
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (_writeError != null) {
      throw FileSystemException('Trace write failed: $_writeError');
    }
  }
}
