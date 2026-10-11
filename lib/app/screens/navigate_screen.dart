import 'package:breadcrumb/app/widgets/ui/ui.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/route_runs.dart';
import 'package:breadcrumb/core/tuning.dart' as tuning;
import 'package:breadcrumb/app/theme.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/app/widgets/arrow_glyph.dart';
import 'package:breadcrumb/app/widgets/trail_view.dart';
import 'scan_screen.dart';

/// Navigation screen, readable while walking and from a projector:
/// - Instruction card: a 64 dp state-coloured arrow box, "N STEPS", the
///   instruction (shrinks to fit two lines, never cut off) and "Then: ...".
///   Off route it turns orange, arrived green; questions get inline buttons.
/// - TrailView filling the middle, north-up and auto-fitted
/// - Dock: confidence gauge, destination, steps left, progress, two buttons
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

  // Card styling only; none of this feeds the tracker or the guide.
  int _backOnRouteFlashes = 0;
  Position? _flashedFor;
  String? _dismissedPrompt;

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
      // UI only: flash the card once when the walker rejoins the route.
      if (position.backOnRoute && !identical(position, _flashedFor)) {
        _flashedFor = position;
        _backOnRouteFlashes++;
      }
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

  @override
  void dispose() {
    _sensorSubscription?.cancel();
    _timer?.cancel();
    super.dispose();
  }


  static const _promptKinds = {
    InstructionKind.arrivingConfirm,
    InstructionKind.confirmPlace,
    InstructionKind.maybePassed,
  };

  /// The transition leg a changeFloor instruction is about: the current leg,
  /// or the one after the current straight run.
  Leg? _floorLeg(RoutePlan? route, Position? position) {
    if (route == null || position == null || route.legs.isEmpty) return null;
    final i = position.legIndex.clamp(0, route.legs.length - 1);
    if (route.legs[i].isTransition) return route.legs[i];
    final j = runEnd(route, i);
    return j + 1 < route.legs.length ? route.legs[j + 1] : null;
  }

  ArrowKind _glyphFor(Instruction? instruction) {
    switch (instruction?.kind) {
      case InstructionKind.offRoute:
      case InstructionKind.maybePassed:
        return ArrowKind.uTurn;
      case InstructionKind.arrivingConfirm:
      case InstructionKind.confirmPlace:
        return ArrowKind.arrival;
      case InstructionKind.changeFloor:
        return _floorLeg(_route, _position)?.kind == CorridorKind.lift ? ArrowKind.lift : ArrowKind.stairs;
      default:
        return arrowKindFor(instruction?.kind);
    }
  }

  Color _toneFor(Instruction? instruction) {
    final kind = instruction?.kind;
    if (kind == InstructionKind.arrive) return BreadcrumbTheme.success;
    if ((_position?.offRoute ?? false) ||
        kind == InstructionKind.offRoute ||
        kind == InstructionKind.maybePassed) {
      return BreadcrumbTheme.offRoute;
    }
    return BreadcrumbTheme.accent;
  }

  Future<void> _openScan() async {
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
  }

  @override
  Widget build(BuildContext context) {
    final showSimulated = _isSimulating || _usedSimulation || (_showDebugButtons && kDebugMode);

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Navigation Error')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded, size: 48, color: BreadcrumbTheme.error),
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
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: BreadcrumbTheme.success,
                    borderRadius: BreadcrumbTheme.borderRadiusLg,
                  ),
                  alignment: Alignment.center,
                  child: const ArrowGlyph(kind: ArrowKind.arrival, size: 44, color: BreadcrumbTheme.onAccent),
                ),
                const SizedBox(height: 24),
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

    final instruction = _currentInstruction;
    final stepsLeft = instruction?.steps;
    final confidence = _getConfidence();
    final nextInstructionText = _getNextInstructionText(route, position, instruction);
    final showPrompt = instruction != null &&
        _promptKinds.contains(instruction.kind) &&
        _dismissedPrompt != instruction.text;

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
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: InstructionCard(
                text: instruction?.text ?? 'Calculating...',
                glyph: _glyphFor(instruction),
                tone: _toneFor(instruction),
                steps: stepsLeft,
                // Off route the "Then" of the route ahead would mislead.
                then: _toneFor(instruction) == BreadcrumbTheme.offRoute ? null : nextInstructionText,
                flashes: _backOnRouteFlashes,
                onYes: showPrompt ? _onImHere : null,
                onNotYet: showPrompt
                    ? () => setState(() => _dismissedPrompt = instruction.text)
                    : null,
              ),
            ),

            // TrailView fills the middle (the hero)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 120),
                  decoration: BoxDecoration(
                    color: BreadcrumbTheme.bg,
                    borderRadius: BreadcrumbTheme.borderRadiusLg,
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    const Text('DEBUG', style: BreadcrumbTheme.eyebrow),
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

            // Dock: confidence, destination, steps left, progress, two buttons
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 12),
              decoration: const BoxDecoration(
                color: BreadcrumbTheme.surface1,
                borderRadius: BorderRadius.vertical(top: Radius.circular(BreadcrumbTheme.radiusLg)),
                border: Border(top: BorderSide(color: BreadcrumbTheme.border)),
              ),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                destName,
                                style: BreadcrumbTheme.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$remainingSteps steps left',
                                style: BreadcrumbTheme.secondary.copyWith(fontFeatures: BreadcrumbTheme.tabular),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (showSimulated) ...[
                          const SizedBox(width: 8),
                          const StatusPill.simulated(),
                        ],
                        const SizedBox(width: 12),
                        ConfidenceGauge(confidence: confidence),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: BreadcrumbTheme.surface3,
                        valueColor: const AlwaysStoppedAnimation<Color>(BreadcrumbTheme.accent),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: PressScale(
                            child: ElevatedButton(
                              style: BreadcrumbTheme.primaryButton,
                              onPressed: _onImHere,
                              child: const FittedBox(fit: BoxFit.scaleDown, child: Text("I'm here")),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PressScale(
                            child: ElevatedButton(
                              style: BreadcrumbTheme.secondaryElevatedButton,
                              onPressed: _openScan,
                              child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Scan sign')),
                            ),
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

/// The instruction card. Same layout in every state; only [tone] (border,
/// arrow box) changes, crossfading over 250 ms.
class InstructionCard extends StatelessWidget {
  const InstructionCard({
    super.key,
    required this.text,
    required this.glyph,
    required this.tone,
    this.steps,
    this.then,
    this.flashes = 0,
    this.onYes,
    this.onNotYet,
  });

  final String text;
  final ArrowKind glyph;
  final Color tone;
  final int? steps;
  final String? then;

  /// Bumped each time the walker gets back on route: one brief accent flash.
  final int flashes;

  /// Inline [Yes] [Not yet] for "Are you at ...?" style questions.
  final VoidCallback? onYes;
  final VoidCallback? onNotYet;

  @override
  Widget build(BuildContext context) {
    final steps = this.steps;
    final then = this.then;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: AnimatedContainer(
                duration: BreadcrumbTheme.medium,
                curve: BreadcrumbTheme.ease,
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: tone,
                  borderRadius: BreadcrumbTheme.borderRadius,
                ),
                alignment: Alignment.center,
                child: AnimatedSwitcher(
                  duration: BreadcrumbTheme.medium,
                  switchInCurve: BreadcrumbTheme.ease,
                  child: ArrowGlyph(
                    key: ValueKey(glyph),
                    kind: glyph,
                    size: 40,
                    color: BreadcrumbTheme.onAccent,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (steps != null && steps > 0) ...[
                    Text(
                      steps == 1 ? '1 STEP' : '$steps STEPS',
                      style: BreadcrumbTheme.eyebrow,
                    ),
                    const SizedBox(height: 4),
                  ],
                  FitInstructionText(text),
                  if (then != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      then,
                      style: BreadcrumbTheme.caption.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (onYes != null) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: PressScale(
                  child: FilledButton(
                    key: const ValueKey('prompt-yes'),
                    onPressed: onYes,
                    child: const Text('Yes'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PressScale(
                  child: OutlinedButton(
                    key: const ValueKey('prompt-not-yet'),
                    onPressed: onNotYet,
                    child: const Text('Not yet'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );

    return Semantics(
      liveRegion: true,
      container: true,
      child: AnimatedContainer(
        duration: BreadcrumbTheme.medium,
        curve: BreadcrumbTheme.ease,
        decoration: BoxDecoration(
          color: BreadcrumbTheme.surface1,
          borderRadius: BreadcrumbTheme.borderRadiusLg,
          border: Border.all(color: tone),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            if (flashes > 0)
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(flashes),
                  tween: Tween(begin: 1, end: 0),
                  duration: const Duration(milliseconds: 900),
                  curve: BreadcrumbTheme.ease,
                  builder: (context, v, _) => ColoredBox(
                    color: BreadcrumbTheme.accent.withValues(alpha: 0.22 * v),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: content,
            ),
          ],
        ),
      ),
    );
  }
}

/// The instruction at 28 sp, stepping down to fit two lines. If even the
/// smallest size needs more lines it wraps: the text is never cut off.
class FitInstructionText extends StatelessWidget {
  const FitInstructionText(this.text, {super.key});

  final String text;

  static const sizes = [28.0, 26.0, 24.0, 22.0, 20.0, 18.0];

  static TextStyle styleFor(double size) => BreadcrumbTheme.headline.copyWith(
        fontSize: size,
        height: 1.18,
        letterSpacing: -0.3,
      );

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        for (final size in sizes) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: styleFor(size)),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
            maxLines: 2,
          )..layout(maxWidth: constraints.maxWidth);
          final fits = !painter.didExceedMaxLines;
          painter.dispose();
          if (fits) return Text(text, style: styleFor(size), maxLines: 2);
        }
        return Text(text, style: styleFor(sizes.last));
      },
    );
  }
}

/// How sure the tracker is of the position, as 4 bars: 4 and 3 accent, 2
/// orange (the app is about to ask "Are you at ...?"), 1 red. Mapped straight
/// from `Position.confidence`; it never shows a number.
class ConfidenceGauge extends StatelessWidget {
  const ConfidenceGauge({super.key, required this.confidence});

  final double confidence;

  static int barsFor(double confidence) {
    if (confidence >= 0.8) return 4;
    if (confidence >= tuning.confidenceAskBelow) return 3;
    if (confidence >= 0.3) return 2;
    return 1;
  }

  static Color colorFor(int bars) => switch (bars) {
        >= 3 => BreadcrumbTheme.accent,
        2 => BreadcrumbTheme.offRoute,
        _ => BreadcrumbTheme.error,
      };

  static const _words = ['very low', 'low', 'good', 'high'];

  int get bars => barsFor(confidence);

  @override
  Widget build(BuildContext context) {
    final bars = this.bars;
    final color = colorFor(bars);
    return Semantics(
      label: 'Position confidence ${_words[bars - 1]}, $bars of 4 bars',
      excludeSemantics: true,
      child: SizedBox(
        width: 28,
        height: 22,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < 4; i++)
              AnimatedContainer(
                duration: BreadcrumbTheme.medium,
                curve: BreadcrumbTheme.ease,
                width: 5,
                height: 7.0 + i * 5,
                decoration: BoxDecoration(
                  color: i < bars ? color : BreadcrumbTheme.surface3,
                  borderRadius: const BorderRadius.all(Radius.circular(1.5)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
