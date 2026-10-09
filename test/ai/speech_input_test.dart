import 'package:breadcrumb/ai/speech_input.dart';
import 'package:flutter_test/flutter_test.dart';

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

    test('stopping without a final result is null', () async {
      final once = ListenOnce()
        ..onResult('coffee', isFinal: false)
        ..onStopped();
      expect(await once.text, isNull);
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
        ..onStopped();
      expect(once.isDone, isTrue);
      expect(await once.text, 'toilet');
      expect(once.error, isNull);
    });
  });
}
