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

/// A recogniser error as a sentence a person can act on, or the code itself
/// when there is nothing more useful to say.
String describeSpeechError(String error) => switch (error) {
  'error_language_unavailable' =>
    'on-device speech pack not installed: download it under Settings > '
        'On-device speech recognition (needs internet once)',
  'error_language_not_supported' => 'this language has no on-device recogniser',
  'error_no_match' || 'error_speech_timeout' => 'no speech heard',
  'error_audio_error' || 'error_audio' => 'microphone busy or unavailable',
  'error_permission' ||
  'error_insufficient_permissions' => 'microphone permission refused',
  'error_busy' || 'error_recognizer_busy' => 'recogniser busy, try again',
  _ => error,
};

/// The outcome of one listen, fed by recogniser callbacks. Pure Dart, so the
/// rules are tested without a microphone: the first final result wins, blank
/// text is null, an error is null, the recogniser stopping or a timeout keeps
/// the last words heard (the text still goes through `PlaceMatcher`), and
/// nothing after the first outcome counts. A stop that comes before the
/// recogniser said it was listening is stale (left over from the previous
/// listen) and is ignored; the timeout still ends a listen that never starts.
class ListenOnce {
  final _done = Completer<String?>();
  String? _lastWords;
  String? _text;
  bool _started = false;

  /// The final text, or null.
  Future<String?> get text => _done.future;
  bool get isDone => _done.isCompleted;

  /// Whether any non-blank words have been heard yet.
  bool get heardWords => _lastWords?.trim().isNotEmpty ?? false;

  /// The error that ended the listen, or that came just after it ended with
  /// no text. Kept for the screen, so a silent failure has a reason.
  String? error;

  /// The recogniser is ready and listening.
  void onListening() => _started = true;

  void onResult(String words, {required bool isFinal}) {
    if (words.trim().isNotEmpty) _lastWords = words;
    if (isFinal) _finish(words);
  }

  void onError(String message) {
    if (!isDone || _text == null) error ??= message;
    _finish(null);
  }

  /// The recogniser stopped. A final result normally arrives before this; if
  /// none did, keep the last words heard.
  void onStopped() {
    if (_started) _finish(_lastWords);
  }

  /// Gave up waiting: keep the last words heard, if any.
  void onTimeout() {
    if (!isDone) error ??= 'timeout';
    _finish(_lastWords);
  }

  void _finish(String? words) {
    if (_done.isCompleted) return;
    final trimmed = words?.trim();
    _text = trimmed == null || trimmed.isEmpty ? null : trimmed;
    _done.complete(_text);
  }
}

class SpeechInput {
  SpeechInput({SpeechToText? speech}) : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  ListenOnce? _current;
  bool _ready = false;

  /// Why the last listen gave null, if it was an error.
  String? lastError;

  /// What the recogniser did during the last listen, like `+812 listening`,
  /// for the debug screen and logcat (`SPEECH`).
  final List<String> lastEvents = [];
  DateTime? _listenStartedAt;

  void _event(String what) {
    final started = _listenStartedAt;
    final ms = started == null
        ? 0
        : DateTime.now().difference(started).inMilliseconds;
    final line = '+$ms $what';
    lastEvents.add(line);
    // ignore: avoid_print
    print('SPEECH $line');
  }

  /// Asks for the microphone if needed and starts the recogniser. False when
  /// the phone has no recogniser or the permission is refused.
  Future<bool> init() async {
    if (_ready) return true;
    try {
      _ready = await _speech.initialize(
        onError: (SpeechRecognitionError e) {
          _event('error ${e.errorMsg}${e.permanent ? ' (permanent)' : ''}');
          _current?.onError(e.errorMsg);
        },
        onStatus: (status) {
          _event('status $status');
          if (status == SpeechToText.listeningStatus) {
            _current?.onListening();
          } else if (status == SpeechToText.doneStatus) {
            _current?.onStopped();
          }
        },
      );
    } catch (e) {
      lastError = '$e';
      _ready = false;
    }
    return _ready;
  }

  /// The languages the on-device recogniser supports, like `en_IN`. On Android
  /// 13+ with the microphone permission, speech_to_text lists the on-device
  /// languages; it never answers when there is no on-device recogniser, hence
  /// the timeout and the empty list. Supported is not installed: on the iQOO
  /// en_IN and hi_IN are listed while their packs are missing, and listening
  /// then fails with `error_language_unavailable` (see [describeSpeechError]).
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
  ///
  /// [pauseFor] only starts counting once the first words are heard:
  /// speech_to_text starts its pause timer when `listen` is called and only
  /// words reset it, so a pause timer from the start cut people off before
  /// they spoke (the recogniser alone takes about a second to warm up).
  Future<String?> listen({
    String localeId = speechLocaleEnglish,
    Duration listenFor = const Duration(seconds: 10),
    Duration pauseFor = const Duration(seconds: 2),
  }) async {
    lastError = null;
    lastEvents.clear();
    _listenStartedAt = DateTime.now();
    _event('listen $localeId');
    if (!await init()) {
      lastError ??= 'speech recogniser not available';
      return null;
    }
    if (_speech.isListening) await _speech.cancel();
    final once = _current = ListenOnce();
    var pauseArmed = false;
    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult r) {
          _event(
            'words "${r.recognizedWords}"${r.finalResult ? ' final' : ''}',
          );
          once.onResult(r.recognizedWords, isFinal: r.finalResult);
          if (!pauseArmed && once.heardWords && !once.isDone) {
            pauseArmed = true;
            try {
              _speech.changePauseFor(pauseFor);
            } catch (_) {
              // Already stopped; the final result or the stop ends the listen.
            }
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          onDevice: true,
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.search,
          listenFor: listenFor,
        ),
      );
    } catch (e) {
      once.onError('$e');
    }
    final timer = Timer(listenFor + const Duration(seconds: 3), () {
      _event('timeout');
      once.onTimeout();
      _speech.stop();
    });
    final text = await once.text;
    timer.cancel();
    // A late error (just after the stop) still explains a null.
    if (text == null) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    lastError = once.error;
    _event(text == null ? 'heard nothing' : 'heard "$text"');
    if (identical(_current, once)) _current = null;
    return text;
  }

  Future<void> cancel() => _speech.cancel();
}
