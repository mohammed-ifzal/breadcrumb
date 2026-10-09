import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:breadcrumb/core/contracts.dart';

class AppSpeaker implements Speaker {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;
    await _tts.setLanguage("en-IN");
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _initialized = true;
  }

  @override
  Future<void> speak(Instruction i) async {
    await _init();
    await _tts.speak(i.text);
  }

  @override
  Future<void> vibrate(InstructionKind k) async {
    final hasVibrator = await Vibration.hasVibrator();
    if (!hasVibrator) return;

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
  }
}
