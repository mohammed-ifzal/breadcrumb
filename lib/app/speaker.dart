import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/tuning.dart' as tuning;

typedef SpeakFn = Future<void> Function(String text);
typedef StopFn = Future<void> Function();
typedef VibrateFn = Future<void> Function(List<int> pattern, int duration);

class AppSpeaker implements Speaker {
  AppSpeaker({
    this.tts,
    this.customSpeak,
    this.customStop,
    this.customVibrate,
  });

  final FlutterTts? tts;
  final SpeakFn? customSpeak;
  final StopFn? customStop;
  final VibrateFn? customVibrate;

  bool _initialized = false;
  String? _lastSpokenText;
  int _lastSpeakTimeMs = 0;
  InstructionKind? _lastInstructionKind;
  int? _lastInstructionSteps;

  Future<void> _init() async {
    if (_initialized) return;
    try {
      final t = tts ?? FlutterTts();
      final dynamic langs = await t.getLanguages;
      if (langs is List) {
        final enIn = langs.firstWhere(
          (l) =>
              l.toString().toLowerCase().contains('en-in') ||
              l.toString().toLowerCase().contains('en_in'),
          orElse: () => null,
        );
        if (enIn != null) {
          await t.setLanguage("en-IN");
        } else {
          final anyEn = langs.firstWhere(
            (l) => l.toString().toLowerCase().startsWith('en'),
            orElse: () => null,
          );
          if (anyEn != null) {
            await t.setLanguage(anyEn.toString());
          }
        }
      }
      await t.setSpeechRate(0.48);
      await t.setVolume(1.0);
      await t.setPitch(1.0);
    } catch (_) {
      // Offline TTS voice missing or unsupported: do not crash.
    }
    _initialized = true;
  }

  /// Formats short, clear navigation-app-style speech text from Instruction.
  static String formatSpeech(Instruction i) {
    switch (i.kind) {
      case InstructionKind.straight:
        return 'Walk straight.';
      case InstructionKind.turnLeft:
        if (i.steps != null && i.steps! <= tuning.turnNowSteps) {
          return 'Turn left now.';
        }
        return 'In ${i.steps ?? 0} steps, turn left.';
      case InstructionKind.turnRight:
        if (i.steps != null && i.steps! <= tuning.turnNowSteps) {
          return 'Turn right now.';
        }
        return 'In ${i.steps ?? 0} steps, turn right.';
      case InstructionKind.turnAround:
        return 'Turn around.';
      case InstructionKind.arrive:
        return 'You have arrived at ${i.placeName ?? "your destination"}.';
      case InstructionKind.offRoute:
        return 'You are off route. Scan a nearby sign.';
      case InstructionKind.rescan:
        return 'You may have passed the turn.';
      case InstructionKind.changeFloor:
        return i.text;
    }
  }

  @override
  Future<void> speak(Instruction i) async {
    final speechText = formatSpeech(i);
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // Speak only on instruction changes, never on every step.
    // Do not repeat the same text within about 4 seconds.
    final bool isKindChange = _lastInstructionKind != i.kind;
    final bool isTurnPromptChange = (i.kind == InstructionKind.turnLeft ||
            i.kind == InstructionKind.turnRight) &&
        _lastInstructionSteps != i.steps &&
        ((i.steps ?? 999) <= tuning.turnNowSteps || (_lastInstructionSteps ?? 0) <= tuning.turnNowSteps);
    final bool isSameTextRecent =
        (_lastSpokenText == speechText) && (nowMs - _lastSpeakTimeMs < 4000);

    if (!isKindChange && !isTurnPromptChange) {
      return;
    }
    if (isSameTextRecent) {
      return;
    }

    _lastInstructionKind = i.kind;
    _lastInstructionSteps = i.steps;
    _lastSpokenText = speechText;
    _lastSpeakTimeMs = nowMs;

    try {
      // Stop current speech first so instructions do not queue.
      final stop = customStop;
      if (stop != null) {
        await stop();
      } else {
        await (tts ?? FlutterTts()).stop();
      }

      final speakFn = customSpeak;
      if (speakFn != null) {
        await speakFn(speechText);
      } else {
        await _init();
        await (tts ?? FlutterTts()).speak(speechText);
      }
    } catch (_) {
      // Offline TTS voice missing or unsupported: do not crash.
    }
  }

  @override
  Future<void> vibrate(InstructionKind k) async {
    // Vibrate only on turnLeft, turnRight, arrive
    if (k != InstructionKind.turnLeft &&
        k != InstructionKind.turnRight &&
        k != InstructionKind.arrive) {
      return;
    }

    try {
      List<int> pattern;
      int fallbackDuration;
      switch (k) {
        case InstructionKind.turnLeft:
          // two short pulses: [0, 100, 100, 100]
          pattern = [0, 100, 100, 100];
          fallbackDuration = 100;
          break;
        case InstructionKind.turnRight:
          // one long pulse: [0, 300]
          pattern = [0, 300];
          fallbackDuration = 300;
          break;
        case InstructionKind.arrive:
          // three short pulses: [0, 100, 100, 100, 100, 100]
          pattern = [0, 100, 100, 100, 100, 100];
          fallbackDuration = 200;
          break;
        default:
          return;
      }

      final vib = customVibrate;
      if (vib != null) {
        await vib(pattern, fallbackDuration);
        return;
      }

      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator != true) return;

      final hasCustom = await Vibration.hasCustomVibrationsSupport();
      if (hasCustom == true) {
        await Vibration.vibrate(pattern: pattern);
      } else {
        await Vibration.vibrate(duration: fallbackDuration);
      }
    } catch (_) {
      // Haptics unavailable or platform call failed: do not crash.
    }
  }
}
