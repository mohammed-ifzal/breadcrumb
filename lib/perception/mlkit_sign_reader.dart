import 'dart:async';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:breadcrumb/core/contracts.dart';

/// Custom text extraction function for headless testing without native ML Kit binaries.
typedef TextExtractFn = Future<String?> Function(String imagePath, TextRecognitionScript script);

/// Owner: Teammate 3.
/// Sign reader using Google ML Kit Text Recognition with Latin and Devanagari scripts.
class MlKitSignReader implements SignReader {
  MlKitSignReader({
    TextRecognizer? latinRecognizer,
    TextRecognizer? devanagariRecognizer,
    this.extractOverride,
  })  : _customLatin = latinRecognizer,
        _customDevanagari = devanagariRecognizer;

  final TextRecognizer? _customLatin;
  final TextRecognizer? _customDevanagari;
  final TextExtractFn? extractOverride;

  TextRecognizer? _latin;
  TextRecognizer? _devanagari;

  TextRecognizer get latin =>
      _customLatin ?? (_latin ??= TextRecognizer(script: TextRecognitionScript.latin));

  TextRecognizer get devanagari =>
      _customDevanagari ??
      (_devanagari ??= TextRecognizer(script: TextRecognitionScript.devanagiri));

  @override
  Future<SignReading?> read(String imagePath) async {
    try {
      String? latinText;
      String? devText;

      final override = extractOverride;
      if (override != null) {
        latinText = await override(imagePath, TextRecognitionScript.latin);
        devText = await override(imagePath, TextRecognitionScript.devanagiri);
      } else {
        final inputImage = InputImage.fromFilePath(imagePath);
        try {
          final resLatin = await latin.processImage(inputImage);
          if (resLatin.text.trim().isNotEmpty) {
            latinText = resLatin.text.trim();
          }
        } catch (_) {}

        try {
          final resDev = await devanagari.processImage(inputImage);
          if (resDev.text.trim().isNotEmpty) {
            devText = resDev.text.trim();
          }
        } catch (_) {}
      }

      final texts = <String>[];
      if (latinText != null && latinText.trim().isNotEmpty) {
        texts.add(latinText.trim());
      }
      if (devText != null && devText.trim().isNotEmpty && devText.trim() != latinText?.trim()) {
        texts.add(devText.trim());
      }

      if (texts.isEmpty) return null;

      final combined = texts.join('\n');
      return SignReading(
        t: DateTime.now().millisecondsSinceEpoch,
        text: combined,
        reader: ReaderKind.mlkit,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    await _customLatin?.close();
    await _customDevanagari?.close();
    await _latin?.close();
    await _devanagari?.close();
  }
}
