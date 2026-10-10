import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:breadcrumb/perception/mlkit_sign_reader.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/place_matcher.dart';

void main() {
  group('MlKitSignReader', () {
    test('reads Latin text and returns mlkit SignReading', () async {
      final reader = MlKitSignReader(
        extractOverride: (path, script) async {
          if (script == TextRecognitionScript.latin) return 'Cafe';
          return null;
        },
      );

      final reading = await reader.read('/dummy/path/cafe.jpg');
      expect(reading, isNotNull);
      expect(reading!.text, 'Cafe');
      expect(reading.reader, ReaderKind.mlkit);
      expect(reading.t, greaterThan(0));
    });

    test('reads Devanagari text and returns mlkit SignReading', () async {
      final reader = MlKitSignReader(
        extractOverride: (path, script) async {
          if (script == TextRecognitionScript.devanagiri) return 'कैफे';
          return null;
        },
      );

      final reading = await reader.read('/dummy/path/cafe_hi.jpg');
      expect(reading, isNotNull);
      expect(reading!.text, 'कैफे');
      expect(reading.reader, ReaderKind.mlkit);
    });

    test('combines bilingual Latin and Devanagari text without duplication', () async {
      final reader = MlKitSignReader(
        extractOverride: (path, script) async {
          if (script == TextRecognitionScript.latin) return 'Reception';
          if (script == TextRecognitionScript.devanagiri) return 'स्वागत कक्ष';
          return null;
        },
      );

      final reading = await reader.read('/dummy/path/reception.jpg');
      expect(reading, isNotNull);
      expect(reading!.text, contains('Reception'));
      expect(reading.text, contains('स्वागत कक्ष'));
    });

    test('returns null when no text is detected', () async {
      final reader = MlKitSignReader(
        extractOverride: (path, script) async => '   ',
      );

      final reading = await reader.read('/dummy/path/blank.jpg');
      expect(reading, isNull);
    });

    test('returns null safely on exception during extraction', () async {
      final reader = MlKitSignReader(
        extractOverride: (path, script) async => throw Exception('file not found'),
      );

      final reading = await reader.read('/invalid/path.jpg');
      expect(reading, isNull);
    });

    test('10 printed sign test cases through MlKitSignReader and PlaceMatcher', () async {
      const venueMap = MapGraph(
        name: 'Venue Map',
        start: 'entrance',
        places: [
          Place(id: 'entrance', name: 'Entrance', aliases: ['main entrance', 'मुख्य द्वार'], kind: PlaceKind.start),
          Place(id: 'reception', name: 'Reception', aliases: ['reception desk', 'स्वागत'], kind: PlaceKind.place),
          Place(id: 'security', name: 'Security', aliases: ['security gate 1', 'सुरक्षा'], kind: PlaceKind.place),
          Place(id: 'elevators', name: 'Elevator Bank', aliases: ['lift', 'elevators', 'लिफ्ट'], kind: PlaceKind.place),
          Place(id: 'cafe', name: 'Cafe', aliases: ['coffee', 'canteen', 'कैफे'], kind: PlaceKind.place),
          Place(id: 'restroom', name: 'Restroom', aliases: ['washroom', 'toilet', 'शौचालय'], kind: PlaceKind.place),
          Place(id: 'conf_a', name: 'Conference Room A', aliases: ['conf room a', 'hall a'], kind: PlaceKind.place),
          Place(id: 'stage', name: 'Stage Side', aliases: ['auditorium', 'मंच'], kind: PlaceKind.place),
          Place(id: 'food_counter', name: 'Food Counter', aliases: ['खाना काउंटर', 'snacks'], kind: PlaceKind.place),
          Place(id: 'exit', name: 'Exit', aliases: ['emergency exit', 'निकास'], kind: PlaceKind.place),
        ],
        corridors: [],
      );

      final matcher = FuzzyPlaceMatcher();

      // 10 printed sign simulations
      final signCases = [
        {'text': 'Entrance', 'expectedId': 'entrance'},
        {'text': 'MAIN ENTRANCE / मुख्य द्वार', 'expectedId': 'entrance'},
        {'text': 'Reception Desk', 'expectedId': 'reception'},
        {'text': 'Security Gate 1', 'expectedId': 'security'},
        {'text': 'Elevators / लिफ्ट', 'expectedId': 'elevators'},
        {'text': 'Cafe & Coffee', 'expectedId': 'cafe'},
        {'text': 'Food Counter / खाना काउंटर', 'expectedId': 'food_counter'},
        {'text': 'Restrooms / Washroom', 'expectedId': 'restroom'},
        {'text': 'Conf Room A', 'expectedId': 'conf_a'},
        {'text': 'Emergency Exit / निकास', 'expectedId': 'exit'},
      ];

      int matchedCount = 0;
      for (final signCase in signCases) {
        final reader = MlKitSignReader(
          extractOverride: (path, script) async => signCase['text'],
        );
        final reading = await reader.read('/signs/test.jpg');
        expect(reading, isNotNull);

        final match = matcher.match(reading!.text, venueMap);
        expect(match, isNotNull, reason: 'Failed to match "${signCase['text']}"');
        expect(match!.placeId, signCase['expectedId']);
        matchedCount++;
      }

      expect(matchedCount, 10);
    });
  });
}
