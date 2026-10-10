import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/app/screens/destination_list_screen.dart';
import 'package:breadcrumb/ai/speech_input.dart';

// Fake SpeechInput that immediately returns null and sets a given error code.
class FakeSpeechInput extends SpeechInput {
  FakeSpeechInput({required this.errorCode}) : super(speech: null);

  final String errorCode;

  @override
  Future<String?> listen({
    String localeId = speechLocaleEnglish,
    Duration listenFor = const Duration(seconds: 10),
    Duration pauseFor = const Duration(seconds: 2),
  }) async {
    lastError = errorCode;
    return null;
  }

  @override
  Future<bool> init() async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SpeechInput originalSpeech;

  setUp(() {
    originalSpeech = Wiring.instance.speechInput;
    Wiring.instance.resetAiForTesting();
    Wiring.instance.map = Wiring.defaultDemoMap;
    Wiring.instance.currentPlaceId = 'entrance';
    Wiring.instance.aiStatus.value = const AiStatus.ready();
    Wiring.instance.isAiReady.value = true;
  });

  tearDown(() {
    Wiring.instance.speechInput = originalSpeech;
    Wiring.instance.resetAiForTesting();
  });

  group('Part 2c: Mic error display', () {
    testWidgets('speech-pack error shows "Speech pack missing on this phone" hint', (tester) async {
      Wiring.instance.speechInput = FakeSpeechInput(errorCode: 'error_language_unavailable');

      await tester.pumpWidget(const MaterialApp(home: DestinationListScreen()));
      await tester.pumpAndSettle();

      // Tap the mic button
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.textContaining('Speech pack missing on this phone'), findsOneWidget);
      expect(find.textContaining('Type the place or pick from the list'), findsOneWidget);
    });

    testWidgets('generic speech error shows error text plus hint', (tester) async {
      Wiring.instance.speechInput = FakeSpeechInput(errorCode: 'error_audio_error');

      await tester.pumpWidget(const MaterialApp(home: DestinationListScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      // describeSpeechError('error_audio_error') == 'microphone busy or unavailable'
      expect(find.textContaining('microphone busy or unavailable'), findsOneWidget);
      expect(find.textContaining('Type the place or pick from the list'), findsOneWidget);
    });

    testWidgets('no crash on mic tap when speech input returns error', (tester) async {
      Wiring.instance.speechInput = FakeSpeechInput(errorCode: 'error_no_match');

      await tester.pumpWidget(const MaterialApp(home: DestinationListScreen()));
      await tester.pumpAndSettle();

      // Must not crash; a message is shown
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Destination list still visible
      expect(find.text('Cafe'), findsOneWidget);
    });
  });
}
