import 'package:breadcrumb/app/widgets/arrow_glyph.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every instruction kind maps to a glyph', () {
    expect(arrowKindFor(InstructionKind.turnLeft), ArrowKind.left);
    expect(arrowKindFor(InstructionKind.turnRight), ArrowKind.right);
    expect(arrowKindFor(InstructionKind.turnAround), ArrowKind.uTurn);
    expect(arrowKindFor(InstructionKind.arrive), ArrowKind.arrival);
    expect(arrowKindFor(InstructionKind.changeFloor), ArrowKind.stairs);
    expect(arrowKindFor(InstructionKind.straight), ArrowKind.straight);
    expect(arrowKindFor(null), ArrowKind.straight);
  });

  testWidgets('each glyph paints without error', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Wrap(
          children: [
            for (final k in ArrowKind.values)
              ArrowGlyph(kind: k, color: Colors.white, size: 32),
          ],
        ),
      ),
    ));
    expect(find.byType(ArrowGlyph), findsNWidgets(ArrowKind.values.length));
  });
}
