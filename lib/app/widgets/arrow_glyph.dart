import 'package:flutter/material.dart';
import 'package:breadcrumb/core/contracts.dart';

enum ArrowKind { straight, left, right, uTurn, arrival, stairs }

/// Maps a guidance [InstructionKind] to the glyph drawn for it.
ArrowKind arrowKindFor(InstructionKind? kind) {
  switch (kind) {
    case InstructionKind.turnLeft:
      return ArrowKind.left;
    case InstructionKind.turnRight:
      return ArrowKind.right;
    case InstructionKind.turnAround:
      return ArrowKind.uTurn;
    case InstructionKind.arrive:
      return ArrowKind.arrival;
    case InstructionKind.changeFloor:
      return ArrowKind.stairs;
    default:
      return ArrowKind.straight;
  }
}

/// A turn arrow drawn with round 4 px strokes (no Material icons).
class ArrowGlyph extends StatelessWidget {
  const ArrowGlyph({super.key, required this.kind, required this.color, this.size = 32});

  final ArrowKind kind;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: ArrowGlyphPainter(kind, color),
    );
  }
}

class ArrowGlyphPainter extends CustomPainter {
  ArrowGlyphPainter(this.kind, this.color);

  final ArrowKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 32 x 32 grid and scaled, so the stroke is 4 px at size 32.
    final s = size.width / 32;
    canvas.scale(s);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void line(List<Offset> pts) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, stroke);
    }

    switch (kind) {
      case ArrowKind.straight:
        line(const [Offset(16, 27), Offset(16, 6)]);
        line(const [Offset(7, 14), Offset(16, 5), Offset(25, 14)]);
      case ArrowKind.left:
        line(const [Offset(24, 27), Offset(24, 14), Offset(10, 14)]);
        line(const [Offset(15, 7), Offset(8, 14), Offset(15, 21)]);
      case ArrowKind.right:
        line(const [Offset(8, 27), Offset(8, 14), Offset(22, 14)]);
        line(const [Offset(17, 7), Offset(24, 14), Offset(17, 21)]);
      case ArrowKind.uTurn:
        final path = Path()
          ..moveTo(9, 27)
          ..lineTo(9, 13)
          ..arcToPoint(const Offset(23, 13), radius: const Radius.circular(7), clockwise: true)
          ..lineTo(23, 22);
        canvas.drawPath(path, stroke);
        line(const [Offset(17, 17), Offset(23, 24), Offset(29, 17)]);
      case ArrowKind.arrival:
        // Map pin with a centre dot.
        final pin = Path()
          ..moveTo(16, 28)
          ..cubicTo(8, 20, 7, 16, 7, 12.5)
          ..arcToPoint(const Offset(25, 12.5), radius: const Radius.circular(9), clockwise: true)
          ..cubicTo(25, 16, 24, 20, 16, 28)
          ..close();
        canvas.drawPath(pin, stroke);
        canvas.drawCircle(const Offset(16, 12.5), 2, Paint()..color = color);
      case ArrowKind.stairs:
        line(const [
          Offset(5, 26),
          Offset(5, 20),
          Offset(12, 20),
          Offset(12, 14),
          Offset(19, 14),
          Offset(19, 8),
          Offset(27, 8),
        ]);
    }
  }

  @override
  bool shouldRepaint(ArrowGlyphPainter old) => old.kind != kind || old.color != color;
}
