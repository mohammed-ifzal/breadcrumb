import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/tuning.dart' as tuning;
import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/app/widgets/trail_view.dart';

class NavigateScreen extends StatefulWidget {
  final String destinationId;
  const NavigateScreen({super.key, required this.destinationId});

  @override
  State<NavigateScreen> createState() => _NavigateScreenState();
}

class _NavigateScreenState extends State<NavigateScreen> {
  RoutePlan? _route;
  Position? _position;
  Instruction? _currentInstruction;
  Timer? _timer;
  bool _isSimulating = false;
  bool _showDebugButtons = false;
  bool _usedSimulation = false;
  String? _errorMessage;
  String? _alreadyTherePlace;
  int _simulatedTimestamp = 0;

  @override
  void initState() {
    super.initState();
    _startNavigation();
  }

  void _startNavigation() {
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
        _position = wiring.tracker.onStep(StepEvent(_simulatedTimestamp));
      } else {
        if (currentPos.legIndex + 1 < currentRoute.legs.length) {
          final nextLeg = currentRoute.legs[currentPos.legIndex + 1];
          final turnAngle = turnBetween(currentLeg.heading, nextLeg.heading);
          if (turnAngle.abs() >= tuning.straightTolerance) {
            _position = wiring.tracker.onTurn(TurnEvent(_simulatedTimestamp, turnAngle));
          } else {
            // Straight boundary: carry on with step
            _position = wiring.tracker.onStep(StepEvent(_simulatedTimestamp));
          }
        } else {
          // Finished route
          _stopSimulation();
          return;
        }
      }

      _updateInstruction();
    });
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
    final oldKind = _currentInstruction?.kind;

    // BUG 2: vibrate only once per new instruction kind
    if (oldKind != newInstruction.kind) {
      wiring.speaker.vibrate(newInstruction.kind);
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
    setState(() {
      _position = wiring.tracker.onStep(StepEvent(_simulatedTimestamp));
      _updateInstruction();
    });
  }

  void _onTurnLeftDebug() {
    final wiring = Wiring.instance;
    _simulatedTimestamp += 500;
    _usedSimulation = true;
    setState(() {
      _position = wiring.tracker.onTurn(TurnEvent(_simulatedTimestamp, 90.0));
      _updateInstruction();
    });
  }

  void _onTurnRightDebug() {
    final wiring = Wiring.instance;
    _simulatedTimestamp += 500;
    _usedSimulation = true;
    setState(() {
      _position = wiring.tracker.onTurn(TurnEvent(_simulatedTimestamp, -90.0));
      _updateInstruction();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Navigation Error')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: const TextStyle(fontSize: 20),
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
        appBar: AppBar(title: const Text('Arrived')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                const SizedBox(height: 16),
                Text(
                  "You're already at $_alreadyTherePlace",
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
    final showSimulated = _isSimulating || _usedSimulation;

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
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade900,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'SIMULATED',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
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
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _currentInstruction?.text ?? 'Calculating...',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          LinearProgressIndicator(
            value: progress,
            minHeight: 10,
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              '${_currentInstruction?.steps ?? 0} steps left on this leg',
              style: const TextStyle(fontSize: 20),
            ),
          ),
          Icon(
            _getArrowIcon(_currentInstruction?.kind),
            size: 100,
            color: Colors.blue,
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(border: Border.all()),
              child: ClipRect(
                child: TrailView(
                  map: wiring.map,
                  route: route,
                  position: position,
                ),
              ),
            ),
          ),
          if (_showDebugButtons && kDebugMode)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('DEBUG: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  OutlinedButton(
                    onPressed: _onStepDebug,
                    child: const Text('+1 step'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _onTurnLeftDebug,
                    child: const Text('turn left'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _onTurnRightDebug,
                    child: const Text('turn right'),
                  ),
                ],
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: _onImHere,
                child: const Text('I am here'),
              ),
              ElevatedButton(
                onPressed: () {},
                child: const Text('Scan sign'),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  IconData _getArrowIcon(InstructionKind? kind) {
    if (kind == null) return Icons.arrow_upward;
    switch (kind) {
      case InstructionKind.turnLeft:
        return Icons.turn_left;
      case InstructionKind.turnRight:
        return Icons.turn_right;
      case InstructionKind.turnAround:
        return Icons.u_turn_left;
      case InstructionKind.arrive:
        return Icons.flag;
      default:
        return Icons.arrow_upward;
    }
  }
}
