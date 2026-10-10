import 'package:breadcrumb/app/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/trail_geometry.dart';
import 'dart:math' as math;

class TrailView extends StatelessWidget {
  final MapGraph? map;
  final ValueListenable<MapGraph>? mapNotifier;
  final RoutePlan? route;
  final Position? position;

  const TrailView({
    super.key,
    this.map,
    this.mapNotifier,
    this.route,
    this.position,
  }) : assert(map != null || mapNotifier != null, 'Either map or mapNotifier must be provided');

  @override
  Widget build(BuildContext context) {
    if (mapNotifier != null) {
      return ValueListenableBuilder<MapGraph>(
        valueListenable: mapNotifier!,
        builder: (context, currentMap, _) {
          return CustomPaint(
            size: Size.infinite,
            painter: TrailPainter(currentMap, route, position),
          );
        },
      );
    }

    return CustomPaint(
      size: Size.infinite,
      painter: TrailPainter(map!, route, position),
    );
  }
}

class TrailPainter extends CustomPainter {
  static const Color labelColor = BreadcrumbTheme.textPrimary;
  static const Color labelBackgroundColor = BreadcrumbTheme.surfaceRaised;
  static const Color canvasBackgroundColor = BreadcrumbTheme.background;

  /// WCAG 2.1 relative luminance for contrast calculation.
  static double relativeLuminance(Color color) {
    double chan(double c) =>
        c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * chan(color.r) +
        0.7152 * chan(color.g) +
        0.0722 * chan(color.b);
  }

  /// WCAG 2.1 contrast ratio between two colors (at least 4.5:1 required for normal text).
  static double contrastRatio(Color c1, Color c2) {
    final l1 = relativeLuminance(c1);
    final l2 = relativeLuminance(c2);
    final lighter = math.max(l1, l2);
    final darker = math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  final MapGraph map;
  final RoutePlan? route;
  final Position? position;

  TrailPainter(this.map, this.route, this.position);

  Offset toOffset(double x, double y, Size size, {List<TrailPoint>? precomputedPoints}) {
    final points = precomputedPoints ?? layoutMap(map);
    if (points.isEmpty) return Offset.zero;

    double minX = points.first.x, maxX = points.first.x;
    double minY = points.first.y, maxY = points.first.y;

    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }

    const padding = 40.0;
    final w = (maxX - minX) == 0 ? 100.0 : (maxX - minX);
    final h = (maxY - minY) == 0 ? 100.0 : (maxY - minY);

    final scaleX = (size.width - padding * 2) / w;
    final scaleY = (size.height - padding * 2) / h;
    final scale = math.min(scaleX, scaleY);

    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;

    return Offset(
      (x - centerX) * scale + size.width / 2,
      -(y - centerY) * scale + size.height / 2,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final points = layoutMap(map);
    if (points.isEmpty) return;

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
        canvas.drawLine(
          toOffset(p1.x, p1.y, size, precomputedPoints: points),
          toOffset(p2.x, p2.y, size, precomputedPoints: points),
          corridorPaint,
        );
      }
    }

    if (route != null && route!.legs.isNotEmpty) {
      for (final leg in route!.legs) {
        final c = map.corridors.cast<Corridor?>().firstWhere(
          (c) => c?.id == leg.corridorId,
          orElse: () => null,
        );
        if (c == null) continue;
        final p1 = pointMap[leg.reversed ? c.to : c.from];
        final p2 = pointMap[leg.reversed ? c.from : c.to];
        if (p1 != null && p2 != null) {
          canvas.drawLine(
            toOffset(p1.x, p1.y, size, precomputedPoints: points),
            toOffset(p2.x, p2.y, size, precomputedPoints: points),
            routePaint,
          );
        }
      }
    }

    final placePaint = Paint()..color = BreadcrumbTheme.accent;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (final p in points) {
      // D19: If this node is hereId ('_here'), draw it as the moving dot
      if (p.placeId == hereId) {
        canvas.drawCircle(
          toOffset(p.x, p.y, size, precomputedPoints: points),
          10,
          Paint()..color = BreadcrumbTheme.danger,
        );
        continue;
      }

      final place = map.places.cast<Place?>().firstWhere(
        (pl) => pl?.id == p.placeId,
        orElse: () => null,
      );
      final offset = toOffset(p.x, p.y, size, precomputedPoints: points);

      if (place == null || place.kind == PlaceKind.junction) {
        canvas.drawCircle(offset, 4, Paint()..color = BreadcrumbTheme.textFaint);
      } else {
        canvas.drawCircle(offset, 8, placePaint);
        textPainter.text = TextSpan(
          text: place.name,
          style: const TextStyle(
            color: labelColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        final textOffset = offset + const Offset(-10, 10);
        final bgRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            textOffset.dx - 4,
            textOffset.dy - 2,
            textPainter.width + 8,
            textPainter.height + 4,
          ),
          const Radius.circular(4),
        );
        canvas.drawRRect(
          bgRect,
          Paint()..color = labelBackgroundColor,
        );
        canvas.drawRRect(
          bgRect,
          Paint()
            ..color = BreadcrumbTheme.border
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
        textPainter.paint(canvas, textOffset);
      }
    }

    // Line 144 guard: Guard against empty legs or route with zero legs
    if (route != null && position != null && route!.legs.isNotEmpty) {
      if (position!.legIndex < route!.legs.length) {
        final leg = route!.legs[position!.legIndex];
        final c = map.corridors.cast<Corridor?>().firstWhere(
          (c) => c?.id == leg.corridorId,
          orElse: () => null,
        );
        if (c != null) {
          final p1 = pointMap[leg.reversed ? c.to : c.from];
          final p2 = pointMap[leg.reversed ? c.from : c.to];
          if (p1 != null && p2 != null) {
            final fraction = leg.steps == 0 ? 0.0 : (position!.stepsAlong / leg.steps);
            final clampedFraction = fraction.clamp(0.0, 1.0);
            final cx = p1.x + (p2.x - p1.x) * clampedFraction;
            final cy = p1.y + (p2.y - p1.y) * clampedFraction;

            canvas.drawCircle(
              toOffset(cx, cy, size, precomputedPoints: points),
              10,
              Paint()..color = Colors.red,
            );
          }
        }
      } else if (position!.legIndex == route!.legs.length) {
        // Arrived
        final leg = route!.legs.last;
        final c = map.corridors.cast<Corridor?>().firstWhere(
          (c) => c?.id == leg.corridorId,
          orElse: () => null,
        );
        if (c != null) {
          final p2 = pointMap[leg.reversed ? c.from : c.to];
          if (p2 != null) {
            canvas.drawCircle(
              toOffset(p2.x, p2.y, size, precomputedPoints: points),
              10,
              Paint()..color = Colors.red,
            );
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(TrailPainter oldDelegate) => true;
}
