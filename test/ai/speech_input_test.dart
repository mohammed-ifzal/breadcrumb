import 'package:breadcrumb/ai/speech_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// A recogniser that fails each locale in [errors] with that error code and
/// hears "coffee" in any other locale. Records the locales it listened in.
class _FakeSpeech implements SpeechToText {
  _FakeSpeech(this.errors);

  final Map<String, String> errors;
  final List<String> listenedIn = [];
  SpeechErrorListener? _onError;
  SpeechStatusListener? _onStatus;

  @override
  Future<bool> initialize({
    SpeechErrorListener? onError,
    SpeechStatusListener? onStatus,
    debugLogging = false,
    Duration finalTimeout = SpeechToText.defaultFinalTimeout,
    List<SpeechConfigOption>? options,
  }) async {
    _onError = onError;
    _onStatus = onStatus;
    return true;
  }

  @override
  bool get isListening => false;

  @override
  Future listen({
    SpeechResultListener? onResult,
    Duration? listenFor,
    Duration? pauseFor,
    String? localeId,
    SpeechSoundLevelChange? onSoundLevelChange,
    cancelOnError = false,
    partialResults = true,
    onDevice = false,
    ListenMode listenMode = ListenMode.confirmation,
    sampleRate = 0,
    SpeechListenOptions? listenOptions,
  }) async {
    final locale = listenOptions!.localeId!;
    listenedIn.add(locale);
    final error = errors[locale];
    if (error != null) {
      _onError?.call(SpeechRecognitionError(error, true));
      return;
    }
    _onStatus?.call(SpeechToText.listeningStatus);
    onResult?.call(
      SpeechRecognitionResult([SpeechRecognitionWords('coffee', null, 1)], 2),
    );
  }

  @override
  void changePauseFor(Duration pauseFor) {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('ListenOnce', () {
    test('the first final result is the text, trimmed', () async {
      final once = ListenOnce()
        ..onResult('where', isFinal: false)
        ..onResult(' where is the stage ', isFinal: true)
        ..onResult('something else', isFinal: true);
      expect(await once.text, 'where is the stage');
      expect(once.error, isNull);
    });

    test('a blank final result is null', () async {
      final once = ListenOnce()..onResult('   ', isFinal: true);
      expect(await once.text, isNull);
    });

    test('an error is null and is kept', () async {
      final once = ListenOnce()
        ..onResult('coff', isFinal: false)
        ..onError('error_language_unavailable');
      expect(await once.text, isNull);
      expect(once.error, 'error_language_unavailable');
    });

    test(
      'stopping without a final result keeps the last words heard',
      () async {
        final once = ListenOnce()
          ..onListening()
          ..onResult('coffee', isFinal: false)
          ..onStopped();
        expect(await once.text, 'coffee');
      },
    );

    test('stopping with nothing heard is null', () async {
      final once = ListenOnce()
        ..onListening()
        ..onStopped();
      expect(await once.text, isNull);
    });

    test('a stop before the recogniser started listening is stale', () async {
      final once = ListenOnce()..onStopped();
      expect(once.isDone, isFalse);
      once
        ..onListening()
        ..onResult('stage', isFinal: true);
      expect(await once.text, 'stage');
    });

    test('an error that arrives after the stop is still kept', () async {
      final once = ListenOnce()
        ..onListening()
        ..onStopped()
        ..onError('error_no_match');
      expect(await once.text, isNull);
      expect(once.error, 'error_no_match');
    });

    test('heardWords turns true on the first non-blank words', () {
      final once = ListenOnce()..onResult('  ', isFinal: false);
      expect(once.heardWords, isFalse);
      once.onResult('wh', isFinal: false);
      expect(once.heardWords, isTrue);
    });

    test('a timeout keeps the last words heard', () async {
      final once = ListenOnce()
        ..onResult('snacks', isFinal: false)
        ..onTimeout();
      expect(await once.text, 'snacks');
      expect(once.error, 'timeout');
    });

    test('a timeout with nothing heard is null', () async {
      final once = ListenOnce()..onTimeout();
      expect(await once.text, isNull);
    });

    test('nothing after the first outcome counts', () async {
      final once = ListenOnce()
        ..onResult('toilet', isFinal: true)
        ..onError('error_client')
        ..onStopped()
        ..onTimeout();
      expect(once.isDone, isTrue);
      expect(await once.text, 'toilet');
      expect(once.error, isNull);
    });
  });

  group('describeSpeechError', () {
    test('a missing language pack says how to install it', () {
      expect(
        describeSpeechError('error_language_unavailable'),
        contains('not installed'),
      );
    });

    test('an unknown code is passed through', () {
      expect(describeSpeechError('error_weird'), 'error_weird');
    });
  });

  group('speechFallbackLocale', () {
    test('a missing en_IN pack falls back to en_US', () {
      expect(
        speechFallbackLocale(speechLocaleEnglish, 'error_language_unavailable'),
        speechLocaleEnglishFallback,
      );
      expect(speechLocaleEnglishFallback, 'en_US');
    });

    test('other errors, other locales and no error do not retry', () {
      expect(
        speechFallbackLocale(speechLocaleEnglish, 'error_no_match'),
        isNull,
      );
      expect(speechFallbackLocale(speechLocaleEnglish, null), isNull);
      expect(
        speechFallbackLocale(speechLocaleHindi, 'error_language_unavailable'),
        isNull,
      );
      expect(
        speechFallbackLocale(
          speechLocaleEnglishFallback,
          'error_language_unavailable',
        ),
        isNull,
      );
    });
  });

  group('SpeechInput.listen', () {
    const short = Duration(seconds: 1);

    test(
      'en_IN unavailable: retries once in en_US and returns its words',
      () async {
        final fake = _FakeSpeech({'en_IN': 'error_language_unavailable'});
        final input = SpeechInput(speech: fake);
        expect(await input.listen(listenFor: short), 'coffee');
        expect(fake.listenedIn, ['en_IN', 'en_US']);
        expect(input.lastError, isNull);
        expect(input.lastEvents, contains(endsWith('listen en_US')));
      },
    );

    test('en_US unavailable too: one retry only, the error is kept', () async {
      final fake = _FakeSpeech({
        'en_IN': 'error_language_unavailable',
        'en_US': 'error_language_unavailable',
      });
      final input = SpeechInput(speech: fake);
      expect(await input.listen(listenFor: short), isNull);
      expect(fake.listenedIn, ['en_IN', 'en_US']);
      expect(input.lastError, 'error_language_unavailable');
    });

    test('en_IN working, other errors and hi_IN do not retry', () async {
      final ok = _FakeSpeech({});
      expect(await SpeechInput(speech: ok).listen(listenFor: short), 'coffee');
      expect(ok.listenedIn, ['en_IN']);

      final noMatch = _FakeSpeech({'en_IN': 'error_no_match'});
      expect(
        await SpeechInput(speech: noMatch).listen(listenFor: short),
        isNull,
      );
      expect(noMatch.listenedIn, ['en_IN']);

      final hindi = _FakeSpeech({'hi_IN': 'error_language_unavailable'});
      expect(
        await SpeechInput(speech: hindi)
            .listen(localeId: speechLocaleHindi, listenFor: short),
        isNull,
      );
      expect(hindi.listenedIn, ['hi_IN']);
    });
  });
}
