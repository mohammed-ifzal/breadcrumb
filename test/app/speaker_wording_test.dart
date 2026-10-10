import 'package:breadcrumb/app/speaker.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

/// D27: the voice says the Guide's own words for orientation, corners and off route.
void main() {
  String speech(InstructionKind kind, String text, {int? steps}) =>
      AppSpeaker.formatSpeech(Instruction(kind: kind, steps: steps, text: text));

  test('orientation instructions (no step count) speak the Guide text', () {
    expect(
      speech(InstructionKind.turnAround, 'Turn around, then walk straight.'),
      'Turn around, then walk straight.',
    );
    expect(
      speech(InstructionKind.turnLeft, 'Turn left, then walk straight.'),
      'Turn left, then walk straight.',
    );
    expect(
      speech(InstructionKind.straight, 'Face Cafe and start walking.'),
      'Face Cafe and start walking.',
    );
  });

  test('near a corner: "Get ready", then "at the corner"; far away unchanged', () {
    expect(
      speech(InstructionKind.turnRight, 'Get ready to turn right.', steps: 3),
      'Get ready to turn right.',
    );
    expect(
      speech(InstructionKind.turnRight, 'Turn right at the corner.', steps: 0),
      'Turn right at the corner.',
    );
    expect(
      speech(InstructionKind.turnRight, 'In about 7 steps, turn right.', steps: 7),
      'In 7 steps, turn right.',
    );
    expect(
      speech(InstructionKind.straight, 'Walk straight, about 9 steps.', steps: 9),
      'Walk straight.',
    );
  });

  test('off route does not send the walker to Scan sign', () {
    const text = "Looks like you went off the path. Go back to the last corner or tap I'm here.";
    expect(speech(InstructionKind.offRoute, text), text);
  });
}
