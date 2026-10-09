import 'package:flutter/material.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/trail_geometry.dart';
import 'dart:math' as math;

class TrailView extends StatelessWidget {
  final MapGraph map;
  final RoutePlan? route;
  final Position? position;

  const TrailView({
    super.key,
    required this.map,
    this.route,
    this.position,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _TrailPainter(map, route, position),
    );
  }
}

class _TrailPainter extends CustomPainter {
  final MapGraph map;
  final RoutePlan? route;
  final Position? position;

  _TrailPainter(this.map, this.route, this.position);

  @override
  void paint(Canvas canvas, Size size) {
    final points = layoutMap(map);
    if (points.isEmpty) return;

    double minX = points.first.x, maxX = points.first.x;
    double minY = points.first.y, maxY = points.first.y;

    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }

    final padding = 40.0;
    final w = (maxX - minX) == 0 ? 100.0 : (maxX - minX);
    final h = (maxY - minY) == 0 ? 100.0 : (maxY - minY);

    final scaleX = (size.width - padding * 2) / w;
    final scaleY = (size.height - padding * 2) / h;
    final scale = math.min(scaleX, scaleY);

    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;

    Offset toOffset(double x, double y) {
      return Offset(
        (x - centerX) * scale + size.width / 2,
        -(y - centerY) * scale + size.height / 2,
      );
    }

    final pointMap = {for (final p in points) p.placeId: p};

    final corridorPaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final routePaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    for (final c in map.corridors) {
      final p1 = pointMap[c.from];
      final p2 = pointMap[c.to];
      if (p1 != null && p2 != null) {
        canvas.drawLine(toOffset(p1.x, p1.y), toOffset(p2.x, p2.y), corridorPaint);
      }
    }

    if (route != null) {
      for (final leg in route!.legs) {
        final c = map.corridors.firstWhere((c) => c.id == leg.corridorId);
        final p1 = pointMap[leg.reversed ? c.to : c.from];
        final p2 = pointMap[leg.reversed ? c.from : c.to];
        if (p1 != null && p2 != null) {
          canvas.drawLine(toOffset(p1.x, p1.y), toOffset(p2.x, p2.y), routePaint);
        }
      }
    }

    final placePaint = Paint()..color = Colors.black;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (final p in points) {
      final place = map.places.firstWhere((pl) => pl.id == p.placeId);
      final offset = toOffset(p.x, p.y);
      
      if (place.kind == PlaceKind.junction) {
        canvas.drawCircle(offset, 4, Paint()..color = Colors.grey);
      } else {
        canvas.drawCircle(offset, 8, placePaint);
        textPainter.text = TextSpan(
          text: place.name,
          style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
        );
        textPainter.layout();
        textPainter.paint(canvas, offset + const Offset(-10, 10));
      }
    }

    if (route != null && position != null) {
      if (position!.legIndex < route!.legs.length) {
        final leg = route!.legs[position!.legIndex];
        final c = map.corridors.firstWhere((c) => c.id == leg.corridorId);
        final p1 = pointMap[leg.reversed ? c.to : c.from];
        final p2 = pointMap[leg.reversed ? c.from : c.to];
        if (p1 != null && p2 != null) {
          final fraction = leg.steps == 0 ? 0.0 : (position!.stepsAlong / leg.steps);
          final clampedFraction = fraction.clamp(0.0, 1.0);
          final cx = p1.x + (p2.x - p1.x) * clampedFraction;
          final cy = p1.y + (p2.y - p1.y) * clampedFraction;
          
          canvas.drawCircle(toOffset(cx, cy), 10, Paint()..color = Colors.red);
        }
      } else if (position!.legIndex == route!.legs.length) {
          // Arrived
          final leg = route!.legs.last;
          final c = map.corridors.firstWhere((c) => c.id == leg.corridorId);
          final p2 = pointMap[leg.reversed ? c.from : c.to];
          if (p2 != null) {
             canvas.drawCircle(toOffset(p2.x, p2.y), 10, Paint()..color = Colors.red);
          }
      }
    }
  }

  @override
  bool shouldRepaint(_TrailPainter oldDelegate) => true;
}
