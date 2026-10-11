import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:breadcrumb/app/theme.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/trail_geometry.dart';

/// The trail, north-up and auto-fitted to the box. No rotation and no camera
/// follow: gyro drift would spin the map.
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
  /// The position dot's pulse ring: one 2 s loop.
  late final AnimationController _controller;

  bool get _animate => widget.animate ?? TrailView.defaultAnimate;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (_animate) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(TrailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldAnimate = oldWidget.animate ?? TrailView.defaultAnimate;
    if (_animate != oldAnimate) {
      if (_animate) {
        if (!_controller.isAnimating) _controller.repeat();
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

  Widget _buildPainter(MapGraph currentMap) {
    // The pulse repaints the painter directly; the widget tree is not rebuilt
    // every frame, and the boundary keeps those repaints off the rest of the screen.
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: TrailPainter(
          currentMap,
          widget.route,
          widget.position,
          pulse: _animate ? _controller : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mapNotifier != null) {
      return ValueListenableBuilder<MapGraph>(
        valueListenable: widget.mapNotifier!,
        builder: (context, currentMap, _) => _buildPainter(currentMap),
      );
    }
    return _buildPainter(widget.map!);
  }
}

/// A label to draw: the node it belongs to, its laid-out text and whether it
/// is placed first (start, destination, next place).
class _Label {
  _Label(this.offset, this.text, this.important);
  final Offset offset;
  final TextPainter text;
  final bool important;
}

enum _NodeStyle { start, destination, next, place, junction }

class TrailPainter extends CustomPainter {
  static const Color labelColor = BreadcrumbTheme.textPrimary;
  static const Color labelBackgroundColor = BreadcrumbTheme.surface2;
  static const Color canvasBackgroundColor = BreadcrumbTheme.bg;

  static const double routeWidth = 6;

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

  // Paints are made once and shared by every painter.
  static Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  static Paint _fill(Color color) => Paint()..color = color;

  static final Paint _bgPaint = _fill(canvasBackgroundColor);
  static final Paint _gridPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.035)
    ..strokeWidth = 1.0;
  static final Paint _trailPaint = _stroke(BreadcrumbTheme.accent, routeWidth);
  static final Paint _offRoutePaint = _stroke(BreadcrumbTheme.borderActive, routeWidth);
  static final Paint _routePaint = _stroke(BreadcrumbTheme.accent, routeWidth);
  static final Paint _walkedPaint = _stroke(BreadcrumbTheme.accentWalked, routeWidth);
  static final Paint _outlinePaint = _fill(canvasBackgroundColor);
  static final Paint _whitePaint = _fill(BreadcrumbTheme.textPrimary);
  static final Paint _placePaint = _fill(BreadcrumbTheme.textSecondary);
  static final Paint _junctionPaint = _fill(BreadcrumbTheme.textMuted);
  static final Paint _startRingPaint = _stroke(BreadcrumbTheme.textPrimary, 2);
  static final Paint _accentFillPaint = _fill(BreadcrumbTheme.accent);
  static final Paint _labelBgPaint = _fill(labelBackgroundColor);
  static final Paint _labelBorderPaint = _stroke(BreadcrumbTheme.borderActive, 1);
  static final Paint _pulsePaint = _stroke(BreadcrumbTheme.accent, 2);
  static const TextStyle _labelStyle = TextStyle(
    fontFamily: BreadcrumbTheme.fontFamily,
    color: labelColor,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  final MapGraph map;
  final RoutePlan? route;
  final Position? position;
  final double pulseValue;

  /// Drives the pulse ring and repaints without rebuilding. Null: a still ring.
  final Animation<double>? pulse;

  TrailPainter(
    this.map,
    this.route,
    this.position, {
    this.pulseValue = 0.0,
    this.pulse,
  }) : super(repaint: pulse);

  late final List<TrailPoint> _points = layoutMap(map);

  // Everything except the pulse is laid out once per size.
  Size? _preparedFor;
  Path? _trail;
  Path? _offRoute;
  Path? _route;
  Path? _walked;
  Offset? _dot;
  final List<(Offset, _NodeStyle)> _nodes = [];
  final List<(_Label, Rect)> _labels = [];

  /// The labels laid out for [size]: text and pill rectangle, for tests.
  @visibleForTesting
  List<(String, Rect)> labelsFor(Size size) {
    _prepare(size);
    return [
      for (final (label, rect) in _labels)
        ((label.text.text! as TextSpan).text!, rect),
    ];
  }

  Offset toOffset(double x, double y, Size size, {List<TrailPoint>? precomputedPoints}) {
    final points = precomputedPoints ?? _points;
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

  Corridor? _corridor(String id) {
    for (final c in map.corridors) {
      if (c.id == id) return c;
    }
    return null;
  }

  Place? _place(String id) {
    for (final p in map.places) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// The node a leg starts from and the node it ends at.
  (String, String)? _ends(Leg leg) {
    final c = _corridor(leg.corridorId);
    if (c == null) return null;
    return leg.reversed ? (c.to, c.from) : (c.from, c.to);
  }

  /// The first named place the route still reaches from the current leg.
  String? _nextPlaceId() {
    final r = route;
    if (r == null || r.legs.isEmpty) return null;
    final from = (position?.legIndex ?? 0).clamp(0, r.legs.length - 1);
    for (var i = from; i < r.legs.length; i++) {
      final end = _ends(r.legs[i])?.$2;
      if (end == null) continue;
      final place = _place(end);
      if (place != null && place.kind != PlaceKind.junction) return end;
    }
    return null;
  }

  /// Where to draw a label for the dot at [dot]: below, above, right or left,
  /// then the same four a step further out, kept inside the canvas. The first
  /// slot clear of [placed] labels and of other places' [dots] wins; failing
  /// that, the first clear of labels only; failing that, below. A place label
  /// is never dropped.
  Offset _labelOffset(Offset dot, Size text, Size canvas, List<Rect> placed, List<Offset> dots) {
    final candidates = [
      for (final gap in [12.0, 20.0 + text.height]) ...[
        dot + Offset(-text.width / 2, gap),
        dot + Offset(-text.width / 2, -gap - text.height),
        dot + Offset(gap + 2, -text.height / 2),
        dot + Offset(-gap - 2 - text.width, -text.height / 2),
      ],
    ];
    Offset clamp(Offset o) => Offset(
          o.dx.clamp(10.0, math.max(10.0, canvas.width - text.width - 10)),
          o.dy.clamp(6.0, math.max(6.0, canvas.height - text.height - 6)),
        );
    bool clearOfLabels(Rect pill) => !placed.any((r) => r.inflate(2).overlaps(pill));
    bool clearOfDots(Rect pill) =>
        !dots.any((d) => d != dot && Rect.fromCircle(center: d, radius: 7).overlaps(pill));
    for (final avoidDots in [true, false]) {
      for (final c in candidates) {
        final o = clamp(c);
        final pill = _pillRect(o, text);
        if (clearOfLabels(pill) && (!avoidDots || clearOfDots(pill))) return o;
      }
    }
    return clamp(candidates.first);
  }

  static Rect _pillRect(Offset textOffset, Size text) =>
      Rect.fromLTWH(textOffset.dx - 8, textOffset.dy - 3, text.width + 16, text.height + 6);

  void _prepare(Size size) {
    if (_preparedFor == size) return;
    _preparedFor = size;
    _nodes.clear();
    _labels.clear();
    _trail = null;
    _offRoute = null;
    _route = null;
    _walked = null;
    _dot = null;
    if (_points.isEmpty) return;

    final pointMap = {for (final p in _points) p.placeId: p};
    Offset at(String id) {
      final p = pointMap[id]!;
      return toOffset(p.x, p.y, size, precomputedPoints: _points);
    }

    // Recorded corridors. With no route they are the trail itself (accent);
    // under a route they step back to neutral so the route is the only accent.
    final r = route;
    final hasRoute = r != null && r.legs.isNotEmpty;
    final corridors = Path();
    for (final c in map.corridors) {
      if (pointMap[c.from] == null || pointMap[c.to] == null) continue;
      final a = at(c.from);
      final b = at(c.to);
      corridors
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy);
    }
    if (hasRoute) {
      _offRoute = corridors;
    } else {
      _trail = corridors;
    }

    // Planned route; the walked part is dimmed.
    if (hasRoute) {
      final ahead = Path();
      final walked = Path();
      final currentLeg = position?.legIndex;
      for (var i = 0; i < r.legs.length; i++) {
        final leg = r.legs[i];
        final ends = _ends(leg);
        if (ends == null || pointMap[ends.$1] == null || pointMap[ends.$2] == null) continue;
        final o1 = at(ends.$1);
        final o2 = at(ends.$2);
        if (currentLeg == null || i > currentLeg) {
          ahead
            ..moveTo(o1.dx, o1.dy)
            ..lineTo(o2.dx, o2.dy);
        } else if (i < currentLeg) {
          walked
            ..moveTo(o1.dx, o1.dy)
            ..lineTo(o2.dx, o2.dy);
        } else {
          final f = leg.steps == 0 ? 0.0 : (position!.stepsAlong / leg.steps).clamp(0.0, 1.0);
          final mid = Offset.lerp(o1, o2, f)!;
          walked
            ..moveTo(o1.dx, o1.dy)
            ..lineTo(mid.dx, mid.dy);
          ahead
            ..moveTo(mid.dx, mid.dy)
            ..lineTo(o2.dx, o2.dy);
        }
      }
      _route = ahead;
      _walked = walked;
    }

    // Nodes and labels.
    final startId = hasRoute ? (_ends(r.legs.first)?.$1 ?? map.start) : map.start;
    final destId = r?.toId;
    final nextId = _nextPlaceId();
    final candidates = <_Label>[];
    for (final p in _points) {
      final offset = at(p.placeId);
      if (p.placeId == hereId) {
        // D19: the walker's position while recording.
        _dot = offset;
        continue;
      }
      final place = _place(p.placeId);
      final isStart = p.placeId == startId || (place != null && place.kind == PlaceKind.start);
      final isDest = (destId != null && p.placeId == destId) ||
          (destId == null && place != null && place.name == 'End of walk');
      final isNext = nextId != null && p.placeId == nextId;
      final style = isStart
          ? _NodeStyle.start
          : isDest
          ? _NodeStyle.destination
          : isNext
          ? _NodeStyle.next
          : (place == null || place.kind == PlaceKind.junction)
          ? _NodeStyle.junction
          : _NodeStyle.place;
      _nodes.add((offset, style));
      if (place != null && place.kind != PlaceKind.junction) {
        final text = TextPainter(
          text: TextSpan(text: place.name, style: _labelStyle),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: math.max(40, size.width * 0.45));
        candidates.add(_Label(offset, text, isStart || isDest || isNext));
      }
    }

    // Every place keeps its label. Important labels are placed first; a label
    // that would collide moves to the next free side of its dot instead.
    candidates.sort((a, b) => (b.important ? 1 : 0) - (a.important ? 1 : 0));
    final placed = <Rect>[];
    final dots = [for (final label in candidates) label.offset];
    for (final label in candidates) {
      final textSize = Size(label.text.width, label.text.height);
      final o = _labelOffset(label.offset, textSize, size, placed, dots);
      final rect = _pillRect(o, textSize);
      placed.add(rect);
      _labels.add((_Label(o, label.text, label.important), rect));
    }

    // The navigation position on the route.
    if (hasRoute && position != null) {
      final pos = position!;
      if (pos.legIndex < r.legs.length) {
        final leg = r.legs[pos.legIndex];
        final ends = _ends(leg);
        if (ends != null && pointMap[ends.$1] != null && pointMap[ends.$2] != null) {
          final f = leg.steps == 0 ? 0.0 : (pos.stepsAlong / leg.steps).clamp(0.0, 1.0);
          _dot = Offset.lerp(at(ends.$1), at(ends.$2), f);
        }
      } else if (pos.legIndex == r.legs.length) {
        // Arrived at the final destination.
        final end = _ends(r.legs.last)?.$2;
        if (end != null && pointMap[end] != null) _dot = at(end);
      }
    }
  }

  void _drawNode(Canvas canvas, Offset o, _NodeStyle style) {
    switch (style) {
      case _NodeStyle.start:
        canvas.drawCircle(o, 6, _outlinePaint);
        canvas.drawCircle(o, 4, _startRingPaint);
      case _NodeStyle.destination:
        canvas.drawCircle(o, 7, _outlinePaint);
        canvas.drawCircle(o, 5, _whitePaint);
        canvas.drawCircle(o, 2.5, _accentFillPaint);
      case _NodeStyle.next:
        canvas.drawCircle(o, 6, _outlinePaint);
        canvas.drawCircle(o, 4, _whitePaint);
      case _NodeStyle.place:
        canvas.drawCircle(o, 6, _outlinePaint);
        canvas.drawCircle(o, 4, _placePaint);
      case _NodeStyle.junction:
        canvas.drawCircle(o, 2.5, _junctionPaint);
    }
  }

  /// 12 dp white dot with an accent ring that grows and fades every 2 s.
  void _drawHereMarker(Canvas canvas, Offset offset) {
    final animated = pulse != null;
    final t = (pulse?.value ?? pulseValue).clamp(0.0, 1.0);
    if (animated || t > 0) {
      _pulsePaint.color = BreadcrumbTheme.accent.withValues(alpha: 0.7 * (1 - t));
      canvas.drawCircle(offset, 8 + 16 * t, _pulsePaint);
    } else {
      _pulsePaint.color = BreadcrumbTheme.accent.withValues(alpha: 0.5);
      canvas.drawCircle(offset, 11, _pulsePaint);
    }
    canvas.drawCircle(offset, 8, _accentFillPaint);
    canvas.drawCircle(offset, 6, _whitePaint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _bgPaint);

    const gridStep = 32.0;
    for (double x = 0; x <= size.width; x += gridStep) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), _gridPaint);
    }
    for (double y = 0; y <= size.height; y += gridStep) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), _gridPaint);
    }

    _prepare(size);
    if (_points.isEmpty) return;

    if (_trail != null) canvas.drawPath(_trail!, _trailPaint);
    if (_offRoute != null) canvas.drawPath(_offRoute!, _offRoutePaint);
    if (_walked != null) canvas.drawPath(_walked!, _walkedPaint);
    if (_route != null) canvas.drawPath(_route!, _routePaint);

    for (final (o, style) in _nodes) {
      _drawNode(canvas, o, style);
    }

    for (final (label, rect) in _labels) {
      final pill = RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2));
      canvas.drawRRect(pill, _labelBgPaint);
      canvas.drawRRect(pill, _labelBorderPaint);
      label.text.paint(canvas, label.offset);
    }

    if (_dot != null) _drawHereMarker(canvas, _dot!);
  }

  @override
  bool shouldRepaint(TrailPainter oldDelegate) {
    return oldDelegate.map != map ||
        oldDelegate.route != route ||
        oldDelegate.position != position ||
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.pulse != pulse;
  }
}
