import 'package:breadcrumb/app/widgets/ui/ui.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/route_runs.dart';
import 'package:breadcrumb/core/tuning.dart' as tuning;
import 'package:breadcrumb/app/theme.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/app/widgets/trail_view.dart';
import 'scan_screen.dart';

/// Google-Maps-style navigation screen:
/// - Top instruction card in accent colour with 56 dp arrow icon + confidence ring
/// - Next instruction strip ("Then: ...")
/// - TrailView filling the middle (the hero)
/// - Bottom sheet with destination name, steps left, progress bar, and two equal buttons
class NavigateScreen extends StatefulWidget {
  final String destinationId;
  final bool simulate;
  const NavigateScreen({super.key, required this.destinationId, this.simulate = false});

  @override
  State<NavigateScreen> createState() => _NavigateScreenState();
}

class _NavigateScreenState extends State<NavigateScreen> {
  RoutePlan? _route;
  Position? _position;
  Instruction? _currentInstruction;
  Timer? _timer;
  StreamSubscription<Object>? _sensorSubscription;
  bool _isSimulating = false;
  bool _showDebugButtons = false;
  bool _usedSimulation = false;
  int? _vibratedTurnLegIndex;
  bool _vibratedArrival = false;
  String? _errorMessage;
  String? _alreadyTherePlace;
  int _simulatedTimestamp = 0;

  @override
  void initState() {
    super.initState();
    _sensorSubscription = Wiring.instance.sensorEvents().listen((event) {
      if (!mounted) return;
      if (event is StepEvent) {
        setState(() {
          _position = Wiring.instance.tracker.onStep(event);
          _updateInstruction();
        });
      } else if (event is TurnEvent) {
        setState(() {
          _position = Wiring.instance.tracker.onTurn(event);
          _updateInstruction();
        });
      }
    });
    _startNavigation();
  }

  void _startNavigation() {
    _vibratedTurnLegIndex = null;
    _vibratedArrival = false;
    final wiring = Wiring.instance;
    final startPlaceId = wiring.effectiveCurrentPlaceId;

    try {
      _route = wiring.planner.plan(wiring.map, startPlaceId, widget.destinationId);
    } on ArgumentError catch (e) {
      setState(() {
        _errorMessage = e.message?.toString() ?? 'Unable to find route to destination.';
      });
      return;
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not plan route: $e';
      });
      return;
    }

    final route = _route!;
    if (route.legs.isEmpty) {
      final destPlace = wiring.map.places.cast<Place?>().firstWhere(
        (p) => p?.id == widget.destinationId,
        orElse: () => null,
      );
      setState(() {
        _alreadyTherePlace = destPlace?.name ?? widget.destinationId;
      });
      return;
    }

    wiring.tracker.setRoute(route);
    _position = wiring.tracker.anchor(startPlaceId);
    _updateInstruction();

    if (widget.simulate) {
      _isSimulating = true;
      _usedSimulation = true;
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        final currentPos = _position;
        final currentRoute = _route;
        if (currentPos == null || currentRoute == null) {
          _stopSimulation();
          return;
        }

        if (currentPos.legIndex >= currentRoute.legs.length) {
          _stopSimulation();
          return;
        }

        final currentLeg = currentRoute.legs[currentPos.legIndex];
        _simulatedTimestamp += 500;

        if (currentPos.stepsAlong < currentLeg.steps) {
          wiring.emitSimulatedEvent(StepEvent(_simulatedTimestamp));
        } else {
          if (currentPos.legIndex + 1 < currentRoute.legs.length) {
            final nextLeg = currentRoute.legs[currentPos.legIndex + 1];
            final turnAngle = turnBetween(currentLeg.heading, nextLeg.heading);
            if (turnAngle.abs() >= tuning.straightTolerance) {
              wiring.emitSimulatedEvent(TurnEvent(_simulatedTimestamp, turnAngle));
            } else {
              // Straight boundary: carry on with step
              wiring.emitSimulatedEvent(StepEvent(_simulatedTimestamp));
            }
          } else {
            // Finished route
            _stopSimulation();
            return;
          }
        }
      });
    }
  }

  void _stopSimulation() {
    _timer?.cancel();
    _timer = null;
    if (mounted) {
      _updateInstruction();
    }
    if (_isSimulating && mounted) {
      setState(() {
        _isSimulating = false;
      });
    }
  }

  void _updateInstruction() {
    final route = _route;
    final position = _position;
    if (route == null || position == null) return;

    final wiring = Wiring.instance;
    final newInstruction = wiring.guide.next(route, position);

    final currentLeg = position.legIndex;
    final isTurnKind = newInstruction.kind == InstructionKind.turnLeft ||
        newInstruction.kind == InstructionKind.turnRight;
    final isTurnNow = isTurnKind && newInstruction.steps == 0;

    if (isTurnNow) {
      if (_vibratedTurnLegIndex != currentLeg) {
        _vibratedTurnLegIndex = currentLeg;
        wiring.speaker.vibrate(newInstruction.kind);
      }
    } else if (newInstruction.kind == InstructionKind.arrive) {
      if (!_vibratedArrival) {
        _vibratedArrival = true;
        wiring.speaker.vibrate(InstructionKind.arrive);
      }
    }

    wiring.speaker.speak(newInstruction);

    setState(() {
      _currentInstruction = newInstruction;
    });
  }

  void _onImHere() {
    final wiring = Wiring.instance;
    final route = _route;
    final position = _position;
    if (route == null || position == null || route.legs.isEmpty) return;

    final legIndex = position.legIndex.clamp(0, route.legs.length - 1);
    final leg = route.legs[legIndex];
    final corridor = wiring.map.corridors.cast<Corridor?>().firstWhere(
      (c) => c?.id == leg.corridorId,
      orElse: () => null,
    );
    if (corridor == null) return;

    final endNodeId = leg.reversed ? corridor.from : corridor.to;

    setState(() {
      _position = wiring.tracker.tapHere(endNodeId);
      _updateInstruction();
    });
  }

  void _onStepDebug() {
    final wiring = Wiring.instance;
    _simulatedTimestamp += 500;
    _usedSimulation = true;
    wiring.emitSimulatedEvent(StepEvent(_simulatedTimestamp));
  }

  void _onTurnLeftDebug() {
    final wiring = Wiring.instance;
    _simulatedTimestamp += 500;
    _usedSimulation = true;
    wiring.emitSimulatedEvent(TurnEvent(_simulatedTimestamp, 90.0));
  }

  void _onTurnRightDebug() {
    final wiring = Wiring.instance;
    _simulatedTimestamp += 500;
    _usedSimulation = true;
    wiring.emitSimulatedEvent(TurnEvent(_simulatedTimestamp, -90.0));
  }

  double _getConfidence() {
    final pos = _position;
    if (pos == null) return 1.0;
    try {
      final dynamic p = pos;
      final c = p.confidence;
      if (c is num) return c.toDouble();
    } catch (_) {}
    return 1.0;
  }

  int _calculateRemainingSteps(RoutePlan? route, Position? position) {
    if (route == null || position == null || route.legs.isEmpty) return 0;
    var total = 0;
    for (var i = position.legIndex; i < route.legs.length; i++) {
      final len = legLength(route.legs[i]);
      if (i == position.legIndex) {
        final rem = len - position.stepsAlong;
        total += rem > 0 ? rem : 0;
      } else {
        total += len;
      }
    }
    return total;
  }

  String? _getNextInstructionText(RoutePlan? route, Position? position, Instruction? currentInstruction) {
    if (route == null || position == null || route.legs.isEmpty) return null;
    if (currentInstruction?.kind == InstructionKind.arrive) return null;

    final i = position.legIndex.clamp(0, route.legs.length - 1);
    final j = runEnd(route, i);

    if (currentInstruction?.kind == InstructionKind.straight) {
      if (j < route.legs.length - 1) {
        final nextLeg = route.legs[j + 1];
        if (nextLeg.isTransition) {
          return 'Then: take ${nextLeg.kind.name}';
        }
        final turn = turnBetween(route.legs[j].heading, nextLeg.heading);
        if (turn.abs() > tuning.turnAroundAngle) {
          return 'Then: turn around';
        } else if (turn > 0) {
          return 'Then: turn left';
        } else if (turn < 0) {
          return 'Then: turn right';
        }
      }
    }

    if (j + 1 < route.legs.length) {
      final nextRunEnd = runEnd(route, j + 1);
      if (nextRunEnd < route.legs.length - 1) {
        final afterLeg = route.legs[nextRunEnd + 1];
        if (afterLeg.isTransition) {
          return 'Then: take ${afterLeg.kind.name}';
        }
        final turn = turnBetween(route.legs[nextRunEnd].heading, afterLeg.heading);
        if (turn.abs() > tuning.turnAroundAngle) {
          return 'Then: turn around';
        } else if (turn > 0) {
          return 'Then: turn left';
        } else if (turn < 0) {
          return 'Then: turn right';
        } else {
          return 'Then: walk straight';
        }
      } else {
        final destPlace = Wiring.instance.map.places.cast<Place?>().firstWhere(
          (p) => p?.id == route.toId,
          orElse: () => null,
        );
        final destName = destPlace?.name ?? 'destination';
        return 'Then: arrive at $destName';
      }
    } else {
      final destPlace = Wiring.instance.map.places.cast<Place?>().firstWhere(
        (p) => p?.id == route.toId,
        orElse: () => null,
      );
      final destName = destPlace?.name ?? 'destination';
      return 'Then: arrive at $destName';
    }
  }

  IconData _getNextInstructionIcon(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('left')) return Icons.turn_left_rounded;
    if (lower.contains('right')) return Icons.turn_right_rounded;
    if (lower.contains('around')) return Icons.u_turn_left_rounded;
    if (lower.contains('stairs') || lower.contains('floor')) return Icons.stairs_rounded;
    if (lower.contains('arrive')) return Icons.flag_rounded;
    return Icons.arrow_upward_rounded;
  }

  IconData _getArrowIcon(InstructionKind? kind) {
    if (kind == null) return Icons.arrow_upward_rounded;
    switch (kind) {
      case InstructionKind.turnLeft:
        return Icons.turn_left_rounded;
      case InstructionKind.turnRight:
        return Icons.turn_right_rounded;
      case InstructionKind.turnAround:
        return Icons.u_turn_left_rounded;
      case InstructionKind.arrive:
        return Icons.flag_rounded;
      case InstructionKind.changeFloor:
        return Icons.stairs_rounded;
      default:
        return Icons.arrow_upward_rounded;
    }
  }

  @override
  void dispose() {
    _sensorSubscription?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showSimulated = _isSimulating || _usedSimulation;

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Navigation Error')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: BreadcrumbTheme.danger),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: BreadcrumbTheme.title,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_alreadyTherePlace != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Arrived'),
          actions: [
            if (showSimulated)
              const Padding(
                padding: EdgeInsets.only(right: 16.0),
                child: Center(
                  child: StatusPill.simulated(),
                ),
              ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (showSimulated) ...[
                  const StatusPill.simulated(),
                  const SizedBox(height: 16),
                ],
                const Icon(Icons.check_circle_outline, size: 64, color: BreadcrumbTheme.accent),
                const SizedBox(height: 16),
                Text(
                  "You're already at $_alreadyTherePlace",
                  style: BreadcrumbTheme.heading,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final wiring = Wiring.instance;
    final route = _route;
    final position = _position;

    // Remaining and progress
    final totalRouteSteps = route != null ? route.totalSteps : 1;
    final remainingSteps = _calculateRemainingSteps(route, position);
    final progress = totalRouteSteps > 0
        ? ((totalRouteSteps - remainingSteps) / totalRouteSteps).clamp(0.0, 1.0)
        : 1.0;

    final destPlace = wiring.map.places.cast<Place?>().firstWhere(
      (p) => p?.id == widget.destinationId,
      orElse: () => null,
    );
    final destName = destPlace?.name ?? widget.destinationId;

    final stepsLeft = _currentInstruction?.steps;
    final confidence = _getConfidence();
    final nextInstructionText = _getNextInstructionText(route, position, _currentInstruction);

    final actionButtonStyle = ElevatedButton.styleFrom(
      backgroundColor: BreadcrumbTheme.surfaceRaised,
      foregroundColor: BreadcrumbTheme.textPrimary,
      side: const BorderSide(color: BreadcrumbTheme.border),
      minimumSize: const Size(BreadcrumbTheme.minTouch, BreadcrumbTheme.minTouch),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      shape: const RoundedRectangleBorder(borderRadius: BreadcrumbTheme.borderRadius),
      textStyle: BreadcrumbTheme.button.copyWith(fontSize: 17),
      elevation: 0,
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          onLongPress: () {
            setState(() {
              _showDebugButtons = !_showDebugButtons;
            });
          },
          child: const Text('Navigating'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.volume_up_rounded),
            tooltip: 'Repeat instruction',
            onPressed: () {
              final instruction = _currentInstruction;
              if (instruction != null) {
                wiring.speaker.speak(instruction);
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // SIMULATED indicator banner
            if (showSimulated)
              Container(
                width: double.infinity,
                color: BreadcrumbTheme.warning.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: const Text(
                  'SIMULATED',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: BreadcrumbTheme.warning,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    letterSpacing: 2.0,
                  ),
                ),
              ),

            // Top instruction card in accent colour
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: BreadcrumbTheme.accent,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: BreadcrumbTheme.accent.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    ConfidenceRing(
                      confidence: confidence,
                      size: 56.0,
                      child: Icon(
                        _getArrowIcon(_currentInstruction?.kind),
                        size: 32,
                        color: BreadcrumbTheme.onAccent,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _currentInstruction?.text ?? 'Calculating...',
                            style: const TextStyle(
                              fontFamily: BreadcrumbTheme.fontFamily,
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              color: BreadcrumbTheme.onAccent,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (stepsLeft != null && stepsLeft > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              stepsLeft == 1 ? '1 step' : '$stepsLeft steps',
                              style: const TextStyle(
                                fontFamily: BreadcrumbTheme.fontFamily,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: BreadcrumbTheme.onAccent,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Next instruction strip ("Then: ...")
            if (nextInstructionText != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: BreadcrumbTheme.surfaceRaised,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: BreadcrumbTheme.border),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _getNextInstructionIcon(nextInstructionText),
                        size: 16,
                        color: BreadcrumbTheme.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          nextInstructionText,
                          style: const TextStyle(
                            fontFamily: BreadcrumbTheme.fontFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: BreadcrumbTheme.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // TrailView fills the middle (the hero)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 120),
                  decoration: BoxDecoration(
                    color: BreadcrumbTheme.surface,
                    borderRadius: BreadcrumbTheme.borderRadius,
                    border: Border.all(color: BreadcrumbTheme.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: TrailView(
                    map: wiring.map,
                    route: route,
                    position: position,
                  ),
                ),
              ),
            ),

            // Dev toggle debug buttons if active
            if (_showDebugButtons && kDebugMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    const Text('DEBUG: ', style: TextStyle(fontWeight: FontWeight.bold, color: BreadcrumbTheme.textSecondary)),
                    OutlinedButton(
                      onPressed: _onStepDebug,
                      child: const Text('+1 step'),
                    ),
                    OutlinedButton(
                      onPressed: _onTurnLeftDebug,
                      child: const Text('turn left'),
                    ),
                    OutlinedButton(
                      onPressed: _onTurnRightDebug,
                      child: const Text('turn right'),
                    ),
                  ],
                ),
              ),

            // Bottom sheet: destination name, steps left, thin progress bar, two equal buttons
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              decoration: const BoxDecoration(
                color: BreadcrumbTheme.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(top: BorderSide(color: BreadcrumbTheme.border, width: 1.5)),
              ),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            destName,
                            style: const TextStyle(
                              fontFamily: BreadcrumbTheme.fontFamily,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: BreadcrumbTheme.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '$remainingSteps steps left',
                            style: const TextStyle(
                              fontFamily: BreadcrumbTheme.fontFamily,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: BreadcrumbTheme.textSecondary,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: BreadcrumbTheme.border,
                        valueColor: const AlwaysStoppedAnimation<Color>(BreadcrumbTheme.accent),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: actionButtonStyle,
                            onPressed: _onImHere,
                            child: const FittedBox(fit: BoxFit.scaleDown, child: Text("I'm here")),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: actionButtonStyle,
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ScanScreen(
                                    destinationId: widget.destinationId,
                                    currentRoute: _route,
                                    onReplan: (newRoute, newPosition) {
                                      setState(() {
                                        _route = newRoute;
                                        _position = newPosition;
                                      });
                                      _updateInstruction();
                                    },
                                  ),
                                ),
                              );
                              _updateInstruction();
                            },
                            child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Scan sign')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small confidence ring around the arrow icon.
/// Uses [confidence] (0.0 to 1.0, defaults to 1.0 full ring);
/// turns amber (warning) when confidence is below 0.5.
class ConfidenceRing extends StatelessWidget {
  const ConfidenceRing({
    super.key,
    required this.confidence,
    required this.child,
    this.size = 56.0,
  });

  final double confidence;
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isLow = confidence < 0.5;
    final ringColor = isLow ? BreadcrumbTheme.warning : BreadcrumbTheme.onAccent;
    final trackColor = BreadcrumbTheme.onAccent.withValues(alpha: 0.22);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _ConfidenceRingPainter(
              progress: confidence.clamp(0.0, 1.0),
              color: ringColor,
              trackColor: trackColor,
              strokeWidth: 3.5,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _ConfidenceRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  _ConfidenceRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress > 0) {
      final ringPaint = Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      const startAngle = -math.pi / 2;
      final sweepAngle = 2 * math.pi * progress;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        ringPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ConfidenceRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor;
  }
}
