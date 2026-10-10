import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:breadcrumb/app/theme.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/trail_geometry.dart';

class TrailView extends StatefulWidget {
  static bool defaultAnimate = !WidgetsBinding.instance.runtimeType.toString().contains('Test');

  final MapGraph? map;
  final ValueListenable<MapGraph>? mapNotifier;
  final RoutePlan? route;
  final Position? position;

  final bool? animate;

  const TrailView({
    super.key,
    this.map,
    this.mapNotifier,
    this.route,
    this.position,
    this.animate,
  }) : assert(map != null || mapNotifier != null, 'Either map or mapNotifier must be provided');

  @override
  State<TrailView> createState() => _TrailViewState();
}

class _TrailViewState extends State<TrailView> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool get _animate => widget.animate ?? TrailView.defaultAnimate;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (_animate) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(TrailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldAnimate = oldWidget.animate ?? TrailView.defaultAnimate;
    if (_animate != oldAnimate) {
      if (_animate) {
        if (!_controller.isAnimating) _controller.repeat(reverse: true);
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildPainter(MapGraph currentMap, double pulse) {
    return CustomPaint(
      size: Size.infinite,
      painter: TrailPainter(
        currentMap,
        widget.route,
        widget.position,
        pulseValue: pulse,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mapNotifier != null) {
      return ValueListenableBuilder<MapGraph>(
        valueListenable: widget.mapNotifier!,
        builder: (context, currentMap, _) {
          if (!_animate) {
            return _buildPainter(currentMap, 0.0);
          }
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => _buildPainter(currentMap, _controller.value),
          );
        },
      );
    }

    if (!_animate) {
      return _buildPainter(widget.map!, 0.0);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => _buildPainter(widget.map!, _controller.value),
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
  final double pulseValue;

  TrailPainter(
    this.map,
    this.route,
    this.position, {
    this.pulseValue = 0.0,
  });

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

    const padding = 52.0;
    final w = (maxX - minX) == 0 ? 100.0 : (maxX - minX);
    final h = (maxY - minY) == 0 ? 100.0 : (maxY - minY);

    final minDim = math.min(size.width, size.height);
    final effectivePadding = minDim > 0 ? math.min(padding, minDim * 0.2) : padding;

    final availW = math.max(10.0, size.width - effectivePadding * 2);
    final availH = math.max(10.0, size.height - effectivePadding * 2);

    final scaleX = availW / w;
    final scaleY = availH / h;
    final scale = math.max(0.0001, math.min(scaleX, scaleY));

    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;

    return Offset(
      (x - centerX) * scale + size.width / 2,
      -(y - centerY) * scale + size.height / 2,
    );
  }

  void _drawHereMarker(Canvas canvas, Offset offset) {
    final clampedPulse = pulseValue.clamp(0.0, 1.0);
    // Outer pulsing halo
    final haloRadius = 10.0 + 8.0 * clampedPulse;
    final haloAlpha = (1.0 - clampedPulse).clamp(0.0, 1.0) * 0.45;
    canvas.drawCircle(
      offset,
      haloRadius,
      Paint()..color = BreadcrumbTheme.danger.withValues(alpha: haloAlpha),
    );
    // Outer contrast ring
    canvas.drawCircle(
      offset,
      9.0,
      Paint()..color = Colors.white,
    );
    // Core marker
    canvas.drawCircle(
      offset,
      7.0,
      Paint()..color = BreadcrumbTheme.danger,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Subtle background grid
    canvas.drawRect(Offset.zero & size, Paint()..color = canvasBackgroundColor);

    final gridPaint = Paint()
      ..color = BreadcrumbTheme.border.withValues(alpha: 0.35)
      ..strokeWidth = 1.0;
    const gridStep = 32.0;
    for (double x = 0; x <= size.width; x += gridStep) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += gridStep) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final points = layoutMap(map);
    if (points.isEmpty) return;

    final pointMap = {for (final p in points) p.placeId: p};

    // 2. Thicker rounded teal corridors
    final corridorPaint = Paint()
      ..color = BreadcrumbTheme.accent.withValues(alpha: 0.35)
      ..strokeWidth = 8.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

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

    // 3. Planned route highlighted on top with a soft glow
    if (route != null && route!.legs.isNotEmpty) {
      final routeGlowPaint = Paint()
        ..color = BreadcrumbTheme.accent.withValues(alpha: 0.4)
        ..strokeWidth = 14.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

      final routeMainPaint = Paint()
        ..color = BreadcrumbTheme.accent
        ..strokeWidth = 6.0
        ..strokeCap = StrokeCap.round;

      for (final leg in route!.legs) {
        final c = map.corridors.cast<Corridor?>().firstWhere(
          (c) => c?.id == leg.corridorId,
          orElse: () => null,
        );
        if (c == null) continue;
        final p1 = pointMap[leg.reversed ? c.to : c.from];
        final p2 = pointMap[leg.reversed ? c.from : c.to];
        if (p1 != null && p2 != null) {
          final o1 = toOffset(p1.x, p1.y, size, precomputedPoints: points);
          final o2 = toOffset(p2.x, p2.y, size, precomputedPoints: points);
          // Glow layer
          canvas.drawLine(o1, o2, routeGlowPaint);
          // Sharp main line
          canvas.drawLine(o1, o2, routeMainPaint);
        }
      }
    }

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final startId = map.start;
    final destId = route?.toId;

    // 4. Place dots with icons by kind, start marker, destination marker
    for (final p in points) {
      final offset = toOffset(p.x, p.y, size, precomputedPoints: points);

      // D19: If this node is hereId ('_here'), draw pulsing moving dot
      if (p.placeId == hereId) {
        _drawHereMarker(canvas, offset);
        continue;
      }

      final place = map.places.cast<Place?>().firstWhere(
        (pl) => pl?.id == p.placeId,
        orElse: () => null,
      );

      final isStart = p.placeId == startId || (place != null && place.kind == PlaceKind.start);
      final isDest = destId != null && p.placeId == destId;

      if (isStart) {
        // Clear start marker: distinct teal ring with white/accent center
        canvas.drawCircle(offset, 13.0, Paint()..color = BreadcrumbTheme.accent.withValues(alpha: 0.3));
        canvas.drawCircle(offset, 10.0, Paint()..color = BreadcrumbTheme.accent);
        canvas.drawCircle(offset, 6.0, Paint()..color = BreadcrumbTheme.onAccent);
        canvas.drawCircle(offset, 3.0, Paint()..color = Colors.white);
      } else if (isDest) {
        // Clear end (destination) marker: glowing amber/warning target
        canvas.drawCircle(offset, 14.0, Paint()..color = BreadcrumbTheme.warning.withValues(alpha: 0.35));
        canvas.drawCircle(offset, 10.0, Paint()..color = BreadcrumbTheme.warning);
        canvas.drawCircle(offset, 6.5, Paint()..color = BreadcrumbTheme.surface);
        canvas.drawCircle(offset, 3.5, Paint()..color = BreadcrumbTheme.warning);
      } else if (place == null || place.kind == PlaceKind.junction) {
        // Junction dot
        canvas.drawCircle(offset, 4.5, Paint()..color = BreadcrumbTheme.textFaint);
        canvas.drawCircle(
          offset,
          4.5,
          Paint()
            ..color = BreadcrumbTheme.border
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      } else {
        // Place dot by kind: place
        canvas.drawCircle(offset, 9.0, Paint()..color = BreadcrumbTheme.surfaceRaised);
        canvas.drawCircle(
          offset,
          9.0,
          Paint()
            ..color = BreadcrumbTheme.accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
        canvas.drawCircle(offset, 4.0, Paint()..color = BreadcrumbTheme.accent);
      }

      // Draw label badge for places and start/dest (skip unlabeled junctions)
      if (place != null && place.kind != PlaceKind.junction) {
        textPainter.text = TextSpan(
          text: place.name,
          style: const TextStyle(
            color: labelColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        final textOffset = offset + const Offset(-10, 12);
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

    // 5. Moving position dot (if route & position provided)
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

            _drawHereMarker(canvas, toOffset(cx, cy, size, precomputedPoints: points));
          }
        }
      } else if (position!.legIndex == route!.legs.length) {
        // Arrived at final destination
        final leg = route!.legs.last;
        final c = map.corridors.cast<Corridor?>().firstWhere(
          (c) => c?.id == leg.corridorId,
          orElse: () => null,
        );
        if (c != null) {
          final p2 = pointMap[leg.reversed ? c.from : c.to];
          if (p2 != null) {
            _drawHereMarker(canvas, toOffset(p2.x, p2.y, size, precomputedPoints: points));
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(TrailPainter oldDelegate) {
    return oldDelegate.map != map ||
        oldDelegate.route != route ||
        oldDelegate.position != position ||
        oldDelegate.pulseValue != pulseValue;
  }
}
