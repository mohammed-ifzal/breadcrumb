/// One spoken request, as text: wraps speech_to_text, listens once and returns
/// the final words or null. Prefers the on-device recogniser and never falls
/// back to a network one (rule 1). The text then goes to the
/// `DestinationResolver`, like typed text.
library;

import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// English (India) and Hindi, as speech_to_text names them.
const String speechLocaleEnglish = 'en_IN';
const String speechLocaleHindi = 'hi_IN';

/// The outcome of one listen, fed by recogniser callbacks. Pure Dart, so the
/// rules are tested without a microphone: the first final result wins, blank
/// text is null, an error or the recogniser stopping without a final result
/// is null, and nothing after the first outcome counts.
class ListenOnce {
  final _done = Completer<String?>();
  String? _lastWords;

  /// The final text, or null.
  Future<String?> get text => _done.future;
  bool get isDone => _done.isCompleted;

  /// The error that ended the listen, if one did.
  String? error;

  void onResult(String words, {required bool isFinal}) {
    _lastWords = words;
    if (isFinal) _finish(words);
  }

  void onError(String message) {
    if (!isDone) error ??= message;
    _finish(null);
  }

  /// The recogniser stopped. A final result normally arrives before this; if
  /// none did, the listen heard nothing usable.
  void onStopped() => _finish(null);

  /// Gave up waiting: keep the last words heard, if any.
  void onTimeout() {
    if (!isDone) error ??= 'timeout';
    _finish(_lastWords);
  }

  void _finish(String? words) {
    if (_done.isCompleted) return;
    final trimmed = words?.trim();
    _done.complete(trimmed == null || trimmed.isEmpty ? null : trimmed);
  }
}

class SpeechInput {
  SpeechInput({SpeechToText? speech}) : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  ListenOnce? _current;
  bool _ready = false;

  /// Why the last listen gave null, if it was an error.
  String? lastError;

  /// Asks for the microphone if needed and starts the recogniser. False when
  /// the phone has no recogniser or the permission is refused.
  Future<bool> init() async {
    if (_ready) return true;
    try {
      _ready = await _speech.initialize(
        onError: (SpeechRecognitionError e) => _current?.onError(e.errorMsg),
        onStatus: (status) {
          if (status == SpeechToText.doneStatus) _current?.onStopped();
        },
      );
    } catch (e) {
      lastError = '$e';
      _ready = false;
    }
    return _ready;
  }

  /// The languages the on-device recogniser supports, like `en_IN`. On Android
  /// 13+ with the microphone permission, speech_to_text lists exactly the
  /// on-device languages; it never answers when there is no on-device
  /// recogniser, hence the timeout and the empty list.
  Future<List<String>> offlineLocales({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!await init()) return const [];
    try {
      final locales = await _speech.locales().timeout(timeout);
      return [for (final l in locales) l.localeId];
    } catch (_) {
      return const [];
    }
  }

  /// Listens once in [localeId] and returns the final text, or null for
  /// silence, an error, no recogniser, or nothing within [listenFor] plus a
  /// grace period.
  Future<String?> listen({
    String localeId = speechLocaleEnglish,
    Duration listenFor = const Duration(seconds: 8),
    Duration pauseFor = const Duration(seconds: 2),
  }) async {
    lastError = null;
    if (!await init()) {
      lastError ??= 'speech recogniser not available';
      return null;
    }
    if (_speech.isListening) await _speech.cancel();
    final once = _current = ListenOnce();
    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult r) =>
            once.onResult(r.recognizedWords, isFinal: r.finalResult),
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          onDevice: true,
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.search,
          listenFor: listenFor,
          pauseFor: pauseFor,
        ),
      );
    } catch (e) {
      once.onError('$e');
    }
    final timer = Timer(listenFor + const Duration(seconds: 3), () {
      once.onTimeout();
      _speech.stop();
    });
    final text = await once.text;
    timer.cancel();
    lastError = once.error;
    if (identical(_current, once)) _current = null;
    return text;
  }

  Future<void> cancel() => _speech.cancel();
}
