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
  static const Color labelBackgroundColor = BreadcrumbTheme.surface;
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
    // Soft pulse
    final haloRadius = 9.0 + 9.0 * clampedPulse;
    final haloAlpha = (1.0 - clampedPulse).clamp(0.0, 1.0) * 0.25;
    canvas.drawCircle(
      offset,
      haloRadius,
      Paint()..color = BreadcrumbTheme.textPrimary.withValues(alpha: haloAlpha),
    );
    // Solid dot with a thin ring in the canvas colour so it reads on the route
    canvas.drawCircle(offset, 8.0, Paint()..color = canvasBackgroundColor);
    canvas.drawCircle(offset, 6.0, Paint()..color = BreadcrumbTheme.textPrimary);
  }

  /// Where to draw a label for the dot at [dot]: below, above, right or left,
  /// whichever first stays clear of [placed] labels, kept inside the canvas.
  Offset _labelOffset(Offset dot, Size text, Size canvas, List<Rect> placed) {
    final candidates = [
      dot + const Offset(-10, 12),
      dot + Offset(-10, -12 - text.height),
      dot + Offset(14, -text.height / 2),
      dot + Offset(-14 - text.width, -text.height / 2),
    ];
    Offset clamp(Offset o) => Offset(
          o.dx.clamp(6.0, math.max(6.0, canvas.width - text.width - 6)),
          o.dy.clamp(4.0, math.max(4.0, canvas.height - text.height - 4)),
        );
    for (final c in candidates) {
      final o = clamp(c);
      final rect = Rect.fromLTWH(o.dx - 4, o.dy - 2, text.width + 8, text.height + 4);
      if (!placed.any((r) => r.inflate(2).overlaps(rect))) return o;
    }
    return clamp(candidates.first);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Background grid at 4% opacity
    canvas.drawRect(Offset.zero & size, Paint()..color = canvasBackgroundColor);

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
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

    // 2. Recorded corridors. With no route they are the trail itself (accent);
    // under a route they step back to neutral so the route is the only accent.
    final hasRoute = route != null && route!.legs.isNotEmpty;
    final corridorPaint = Paint()
      ..color = hasRoute ? BreadcrumbTheme.border : BreadcrumbTheme.accent
      ..strokeWidth = 6.0
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

    // 3. Planned route: 6 px, round caps; the walked part is dimmed to 40%.
    if (hasRoute) {
      final routeMainPaint = Paint()
        ..color = BreadcrumbTheme.accent
        ..strokeWidth = 6.0
        ..strokeCap = StrokeCap.round;
      final walkedPaint = Paint()
        ..color = BreadcrumbTheme.accent.withValues(alpha: 0.4)
        ..strokeWidth = 6.0
        ..strokeCap = StrokeCap.round;
      final currentLeg = position?.legIndex;

      for (var i = 0; i < route!.legs.length; i++) {
        final leg = route!.legs[i];
        final c = map.corridors.cast<Corridor?>().firstWhere(
          (c) => c?.id == leg.corridorId,
          orElse: () => null,
        );
        if (c == null) continue;
        final p1 = pointMap[leg.reversed ? c.to : c.from];
        final p2 = pointMap[leg.reversed ? c.from : c.to];
        if (p1 == null || p2 == null) continue;
        final o1 = toOffset(p1.x, p1.y, size, precomputedPoints: points);
        final o2 = toOffset(p2.x, p2.y, size, precomputedPoints: points);
        if (currentLeg == null || i > currentLeg) {
          canvas.drawLine(o1, o2, routeMainPaint);
        } else if (i < currentLeg) {
          canvas.drawLine(o1, o2, walkedPaint);
        } else {
          final f = leg.steps == 0
              ? 0.0
              : (position!.stepsAlong / leg.steps).clamp(0.0, 1.0);
          final mid = Offset.lerp(o1, o2, f)!;
          canvas.drawLine(mid, o2, routeMainPaint);
          canvas.drawLine(o1, mid, walkedPaint);
        }
      }
    }

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final startId = route != null && route!.legs.isNotEmpty
        ? (() {
            final firstLeg = route!.legs.first;
            final c = map.corridors.cast<Corridor?>().firstWhere(
              (c) => c?.id == firstLeg.corridorId,
              orElse: () => null,
            );
            return c != null ? (firstLeg.reversed ? c.to : c.from) : map.start;
          })()
        : map.start;
    final destId = route?.toId;
    final placedLabels = <Rect>[];

    // 4. Place dots with label pills, start marker, destination marker
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
      final isDest = (destId != null && p.placeId == destId) ||
          (destId == null && place != null && place.name == 'End of walk');

      if (isStart) {
        // Start: hollow ring
        canvas.drawCircle(offset, 6.0, Paint()..color = canvasBackgroundColor);
        canvas.drawCircle(
          offset,
          5.0,
          Paint()
            ..color = BreadcrumbTheme.textPrimary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
      } else if (isDest) {
        // Destination: larger solid dot
        canvas.drawCircle(offset, 8.0, Paint()..color = canvasBackgroundColor);
        canvas.drawCircle(offset, 6.0, Paint()..color = BreadcrumbTheme.textPrimary);
        canvas.drawCircle(offset, 2.0, Paint()..color = canvasBackgroundColor);
      } else if (place == null || place.kind == PlaceKind.junction) {
        // Junction: tiny neutral dot
        canvas.drawCircle(offset, 2.5, Paint()..color = BreadcrumbTheme.textFaint);
      } else {
        // Marked place: small dot
        canvas.drawCircle(offset, 5.0, Paint()..color = canvasBackgroundColor);
        canvas.drawCircle(offset, 3.5, Paint()..color = BreadcrumbTheme.textSecondary);
      }

      // Draw label badge for places and start/dest (skip unlabeled junctions)
      if (place != null && place.kind != PlaceKind.junction) {
        textPainter.text = TextSpan(
          text: place.name,
          style: const TextStyle(
            fontFamily: BreadcrumbTheme.fontFamily,
            color: labelColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        );
        textPainter.layout();
        final textOffset = _labelOffset(
          offset,
          Size(textPainter.width, textPainter.height),
          size,
          placedLabels,
        );
        final labelRect = Rect.fromLTWH(
          textOffset.dx - 6,
          textOffset.dy - 2,
          textPainter.width + 12,
          textPainter.height + 4,
        );
        placedLabels.add(labelRect);
        final bgRect = RRect.fromRectAndRadius(
          labelRect,
          Radius.circular(labelRect.height / 2),
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
