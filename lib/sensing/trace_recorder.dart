import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Local recorder status; the path remains available after stop or failure.
class TraceState {
  const TraceState({this.recording = false, this.path, this.error});
  final bool recording;
  final String? path;
  final String? error;
}

/// App-private JSONL traces. A failed session stops and logs exactly once.
class TraceRecorder {
  TraceRecorder({
    Future<Directory> Function()? documentsDirectory,
    IOSink Function(File)? openSink,
    void Function(String)? logger,
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       _openSink = openSink ?? ((file) => file.openWrite()),
       _logger = logger ?? debugPrint;

  final Future<Directory> Function() _documentsDirectory;
  final IOSink Function(File) _openSink;
  final void Function(String) _logger;
  final state = ValueNotifier<TraceState>(const TraceState());
  IOSink? _sink;
  Future<void>? _opening;
  Future<void>? _closing;
  bool _failed = false;
  int _session = 0;

  Future<void> start(Map<String, Object?> meta) {
    if (_sink != null || _opening != null) {
      return Future.error(StateError('A trace is already active.'));
    }
    final opening = _open(Map.of(meta)).whenComplete(() => _opening = null);
    _opening = opening;
    return opening;
  }

  Future<void> _open(Map<String, Object?> meta) async {
    await _closing;
    _closing = null;
    _failed = false;
    final session = ++_session;
    state.value = const TraceState();
    try {
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
      state.value = TraceState(path: file.path);
      await file.create(exclusive: true);
      final sink = _openSink(file);
      _sink = sink;
      // Observe async disk errors immediately, including failures before stop.
      unawaited(
        sink.done.then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            if (session == _session) _fail(error);
          },
        ),
      );
      state.value = TraceState(recording: true, path: file.path);
      sink.writeln(firstLine);
    } catch (error) {
      _fail(error);
    }
  }

  void _fail(Object error) {
    if (_failed) return;
    _failed = true;
    final sink = _sink;
    _sink = null;
    // Begin cleanup before notifying listeners, which may call stop immediately.
    if (sink != null) _closing ??= _finish(sink, flush: false);
    state.value = TraceState(path: state.value.path, error: error.toString());
    _logger('Trace stopped after write failure: $error');
  }

  void record(Map<String, Object?> event) {
    final sink = _sink;
    if (sink == null) return;
    try {
      sink.writeln(jsonEncode(event));
    } catch (error) {
      _fail(error);
    }
  }

  void mark(int t, String note) =>
      record({'type': 'mark', 't': t, 'note': note});

  Future<void> _finish(IOSink sink, {required bool flush}) async {
    if (flush) {
      try {
        await sink.flush();
      } catch (error) {
        _fail(error);
      }
    }
    try {
      await sink.close();
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> stop() async {
    await _opening;
    final sink = _sink;
    _sink = null;
    if (sink != null) {
      _closing ??= _finish(sink, flush: true);
      state.value = TraceState(
        path: state.value.path,
        error: state.value.error,
      );
    }
    await _closing;
  }

  Future<void> dispose() async {
    await stop();
    state.dispose();
  }
}
