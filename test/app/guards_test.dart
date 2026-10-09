import 'package:breadcrumb/app/speaker.dart';
import 'package:breadcrumb/app/screens/permissions_screen.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Crash-proofing guards', () {
    test('AppSpeaker does not crash if TTS fails or en-IN voice is missing', () async {
      final speaker = AppSpeaker();

      // Ensure that calling speak does not throw even if platform channels are unavailable or fail
      await expectLater(
        speaker.speak(const Instruction(
          kind: InstructionKind.turnLeft,
          text: 'Turn left now',
        )),
        completes,
      );
    });

    test('AppSpeaker does not crash if vibration is unavailable', () async {
      final speaker = AppSpeaker();

      // Ensure that calling vibrate for various instructions completes without unhandled exception
      await expectLater(speaker.vibrate(InstructionKind.turnLeft), completes);
      await expectLater(speaker.vibrate(InstructionKind.turnRight), completes);
      await expectLater(speaker.vibrate(InstructionKind.arrive), completes);
      await expectLater(speaker.vibrate(InstructionKind.straight), completes);
    });

    testWidgets('PermissionsScreen renders gracefully if permission request fails or is refused', (tester) async {
      // Mock permission_handler channel to simulate refusal
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        (call) async {
          if (call.method == 'requestPermissions') {
            return {
              0: 0, // PermissionStatus.denied
              1: 0,
              2: 0,
            };
          }
          return null;
        },
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: PermissionsScreen(),
        ),
      );

      await tester.pumpAndSettle();

      // Verifies the refusal UI is shown gracefully instead of a crash
      expect(find.byType(ElevatedButton), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });
  });
}
