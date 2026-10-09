import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:breadcrumb/core/contracts.dart';

class AppSpeaker implements Speaker {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;
    try {
      final dynamic langs = await _tts.getLanguages;
      if (langs is List &&
          langs.any((l) =>
              l.toString().toLowerCase().contains('en-in') ||
              l.toString().toLowerCase().contains('en_in'))) {
        await _tts.setLanguage("en-IN");
      }
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    } catch (_) {
      // Offline TTS voice missing or unsupported: do not crash.
    }
    _initialized = true;
  }

  @override
  Future<void> speak(Instruction i) async {
    try {
      await _init();
      await _tts.speak(i.text);
    } catch (_) {
      // Catch any TTS failures so navigation never crashes.
    }
  }

  @override
  Future<void> vibrate(InstructionKind k) async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator != true) return;

      final hasCustom = await Vibration.hasCustomVibrationsSupport();
      if (hasCustom == true) {
        switch (k) {
          case InstructionKind.turnLeft:
            await Vibration.vibrate(pattern: [0, 100, 100, 100]);
            break;
          case InstructionKind.turnRight:
            await Vibration.vibrate(pattern: [0, 300]);
            break;
          case InstructionKind.arrive:
            await Vibration.vibrate(pattern: [0, 100, 100, 100, 100, 100]);
            break;
          default:
            break;
        }
      } else {
        await Vibration.vibrate(duration: 200);
      }
    } catch (_) {
      // Haptics unavailable or platform call failed: do not crash.
    }
  }
}
