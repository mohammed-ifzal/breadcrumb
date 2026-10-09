import 'package:flutter/material.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/app/widgets/trail_view.dart';
import 'dart:async';

class NavigateScreen extends StatefulWidget {
  final String destinationId;
  const NavigateScreen({super.key, required this.destinationId});

  @override
  State<NavigateScreen> createState() => _NavigateScreenState();
}

class _NavigateScreenState extends State<NavigateScreen> {
  late RoutePlan _route;
  late Position _position;
  Instruction? _currentInstruction;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startNavigation();
  }

  void _startNavigation() {
    final wiring = Wiring.instance;
    _route = wiring.planner.plan(wiring.map, wiring.map.start, widget.destinationId);
    wiring.tracker.setRoute(_route);
    _position = wiring.tracker.anchor(wiring.map.start);
    _updateInstruction();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_position.legIndex >= _route.legs.length) {
        timer.cancel();
        return;
      }
      
      final currentLeg = _route.legs[_position.legIndex];
      if (_position.stepsAlong < currentLeg.steps) {
         _position = wiring.tracker.onStep(const StepEvent(0));
      } else {
         _position = wiring.tracker.onTurn(const TurnEvent(0, 90));
      }
      
      _updateInstruction();
    });
  }

  void _updateInstruction() {
    final wiring = Wiring.instance;
    final newInstruction = wiring.guide.next(_route, _position);
    
    if (_currentInstruction?.text != newInstruction.text) {
      wiring.speaker.speak(newInstruction);
      wiring.speaker.vibrate(newInstruction.kind);
    }
    
    setState(() {
      _currentInstruction = newInstruction;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wiring = Wiring.instance;
    final totalSteps = _route.totalSteps;
    int stepsTaken = 0;
    for (int i = 0; i < _position.legIndex; i++) {
       stepsTaken += _route.legs[i].steps;
    }
    stepsTaken += _position.stepsAlong;
    
    final progress = totalSteps > 0 ? stepsTaken / totalSteps : 0.0;

    return Scaffold(
      appBar: AppBar(title: const Text('Navigating')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _currentInstruction?.text ?? 'Calculating...',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 10,
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text('${_currentInstruction?.steps ?? 0} steps left on this leg', style: const TextStyle(fontSize: 20)),
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
                  route: _route,
                  position: _position,
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: () {
                   setState(() {
                      _position = wiring.tracker.tapHere(wiring.map.start);
                      _updateInstruction();
                   });
                },
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
    switch(kind) {
      case InstructionKind.turnLeft: return Icons.turn_left;
      case InstructionKind.turnRight: return Icons.turn_right;
      case InstructionKind.turnAround: return Icons.u_turn_left;
      case InstructionKind.arrive: return Icons.flag;
      default: return Icons.arrow_upward;
    }
  }
}
