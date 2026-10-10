import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/tuning.dart' as tuning;
import 'package:breadcrumb/app/theme.dart';
import 'package:breadcrumb/app/widgets/ui/ui.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/app/widgets/trail_view.dart';
import 'scan_screen.dart';

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

    // BUG 2b: Vibrate turnLeft/turnRight exactly ONCE per leg, at "Turn left/right at
    // the corner" (steps == 0, D27), not at "Get ready to turn".
    // Arrive vibrates once on arrival. Straight never vibrates.
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

    // BUG 4: speaker manages text formatting, cooldown, and stopping previous speech
    wiring.speaker.speak(newInstruction);

    setState(() {
      _currentInstruction = newInstruction;
    });
  }

  /// BUG 3: "I am here" advances to the node at the end of the current leg (the next waypoint),
  /// rather than resetting to the start place.
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

    final route = _route;
    final position = _position;
    final wiring = Wiring.instance;

    final totalSteps = route?.totalSteps ?? 0;
    int stepsTaken = 0;
    if (route != null && position != null) {
      for (int i = 0; i < position.legIndex && i < route.legs.length; i++) {
        stepsTaken += route.legs[i].steps;
      }
      stepsTaken += position.stepsAlong;
    }

    final progress = totalSteps > 0 ? (stepsTaken / totalSteps).clamp(0.0, 1.0) : 0.0;

    // Equal secondary buttons for "I am here" and "Scan sign".
    final actionButton = ElevatedButton.styleFrom(
      backgroundColor: BreadcrumbTheme.surface,
      foregroundColor: BreadcrumbTheme.textPrimary,
      side: const BorderSide(color: BreadcrumbTheme.border),
      minimumSize: const Size(BreadcrumbTheme.minTouch, BreadcrumbTheme.minTouch),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      shape: const RoundedRectangleBorder(borderRadius: BreadcrumbTheme.borderRadius),
      textStyle: BreadcrumbTheme.button.copyWith(fontSize: 17),
      elevation: 0,
    );
    final stepsLeft = _currentInstruction?.steps;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: kDebugMode
              ? () {
                  setState(() => _showDebugButtons = !_showDebugButtons);
                }
              : null,
          child: const Text('Navigating'),
        ),
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Short screens (360x640 at font scale 1.3) get a smaller arrow, tighter
          // spacing and a smaller trail card so everything fits without scrolling.
          final compact = constraints.maxHeight < 700;
          final gap = compact ? 12.0 : 20.0;
          final arrowCircle = compact ? 88.0 : 120.0;
          final trailHeight = constraints.maxHeight * (compact ? 0.32 : 0.40);

          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showSimulated)
                  Container(
                    width: double.infinity,
                    color: Colors.amber.shade800,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: const Text(
                      'SIMULATED',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ),

                // Live instruction: 28 sp, bold, centred, at most two lines.
                Padding(
                  padding: EdgeInsets.fromLTRB(24, gap, 24, 0),
                  child: Text(
                    _currentInstruction?.text ?? 'Calculating...',
                    style: BreadcrumbTheme.liveInstruction.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      letterSpacing: -0.3,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Distance pill ("12 steps"); hidden when the instruction has no count.
                if (stepsLeft != null)
                  Padding(
                    padding: EdgeInsets.only(top: gap * 0.6),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: BreadcrumbTheme.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: BreadcrumbTheme.accent.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          stepsLeft == 1 ? '1 step' : '$stepsLeft steps',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: BreadcrumbTheme.accent,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Thin progress bar with rounded ends.
                Padding(
                  padding: EdgeInsets.fromLTRB(32, gap, 32, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: BreadcrumbTheme.surfaceRaised,
                      valueColor: const AlwaysStoppedAnimation<Color>(BreadcrumbTheme.accent),
                    ),
                  ),
                ),

                // Arrow in a soft teal circle.
                Padding(
                  padding: EdgeInsets.only(top: gap),
                  child: Center(
                    child: Container(
                      width: arrowCircle,
                      height: arrowCircle,
                      decoration: BoxDecoration(
                        color: BreadcrumbTheme.accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: BreadcrumbTheme.accent.withValues(alpha: 0.30),
                        ),
                      ),
                      child: Icon(
                        _getArrowIcon(_currentInstruction?.kind),
                        size: arrowCircle * 0.6,
                        color: BreadcrumbTheme.accent,
                      ),
                    ),
                  ),
                ),

                // Trail card: the hero, about 40% of the screen.
                Padding(
                  padding: EdgeInsets.fromLTRB(16, gap, 16, 0),
                  child: Container(
                    height: trailHeight,
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

                // Dev toggle debug buttons
                if (_showDebugButtons && kDebugMode)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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

                // Actions row: "I am here" & "Scan sign"
                Padding(
                  padding: EdgeInsets.fromLTRB(16, gap, 16, gap),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: actionButton,
                          onPressed: _onImHere,
                          child: const Text('I am here'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: actionButton,
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
                          child: const Text('Scan sign'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
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
      default:
        return Icons.arrow_upward_rounded;
    }
  }
}
