import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/app/widgets/trail_view.dart';

class ReplayScreen extends StatefulWidget {
  final String? initialTraceContent;
  const ReplayScreen({super.key, this.initialTraceContent});

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  String? _statusMessage;
  bool _isPlaying = false;
  Position? _position;
  Instruction? _currentInstruction;
  RoutePlan? _route;

  @override
  void initState() {
    super.initState();
    if (widget.initialTraceContent != null) {
      _loadAndPlayTrace(widget.initialTraceContent!);
    }
  }

  Future<void> _pickFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jsonl', 'txt'],
      );
      if (files.isNotEmpty && files.first.path != null) {
        final file = File(files.first.path!);
        final content = await file.readAsString();
        await _loadAndPlayTrace(content);
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error picking trace file: $e';
      });
    }
  }

  Future<void> _loadAndPlayTrace(String content) async {
    final lines = content.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    if (lines.isEmpty) {
      setState(() {
        _statusMessage = 'Trace file is empty.';
      });
      return;
    }

    Map<String, dynamic> meta;
    try {
      meta = jsonDecode(lines.first) as Map<String, dynamic>;
      if (meta['type'] != 'meta') {
        setState(() {
          _statusMessage = 'Malformed trace: first line must be type "meta".';
        });
        return;
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Malformed trace: invalid meta header ($e).';
      });
      return;
    }

    final wiring = Wiring.instance;
    final fromId = meta['from'] as String? ?? wiring.map.start;
    final toId = meta['to'] as String? ?? wiring.map.places.firstWhere((p) => p.kind == PlaceKind.place).id;

    try {
      _route = wiring.planner.plan(wiring.map, fromId, toId);
      wiring.tracker.setRoute(_route!);
      _position = wiring.tracker.anchor(fromId);
      _currentInstruction = wiring.guide.next(_route!, _position!);
    } catch (e) {
      setState(() {
        _statusMessage = 'Unable to plan route for trace: $e';
      });
      return;
    }

    setState(() {
      _isPlaying = true;
      _statusMessage = 'Replaying trace for ${meta["map"] ?? "map"}...';
    });

    int? prevT;
    for (int i = 1; i < lines.length; i++) {
      if (!mounted) break;

      final line = lines[i];
      Map<String, dynamic> event;
      try {
        event = jsonDecode(line) as Map<String, dynamic>;
      } catch (e) {
        setState(() {
          _statusMessage = 'Malformed trace line at $i: $line';
          _isPlaying = false;
        });
        return;
      }

      final type = event['type'] as String?;
      final t = (event['t'] as num?)?.toInt() ?? 0;

      if (prevT != null && t > prevT) {
        final delayMs = (t - prevT).clamp(0, 1000);
        await Future.delayed(Duration(milliseconds: delayMs));
      }
      prevT = t;

      if (!mounted) break;

      if (type == 'motion') {
        final accel = (event['accel'] as num?)?.toDouble() ?? 0.0;
        final yawRate = (event['yawRate'] as num?)?.toDouble() ?? 0.0;

        final step = wiring.stepDetector.onMotion(t, accel);
        if (step != null) {
          _position = wiring.tracker.onStep(step);
        }

        final turn = wiring.turnDetector.onMotion(t, yawRate);
        if (turn != null) {
          _position = wiring.tracker.onTurn(turn);
        }
      } else if (type == 'step') {
        _position = wiring.tracker.onStep(StepEvent(t));
      }

      if (_route != null && _position != null) {
        _currentInstruction = wiring.guide.next(_route!, _position!);
      }

      setState(() {});
    }

    if (mounted) {
      setState(() {
        _isPlaying = false;
        _statusMessage = 'Replay finished.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wiring = Wiring.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Replay Mode'),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.deepPurple,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'REPLAY',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.deepPurple,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: const Text(
              'REPLAY',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                letterSpacing: 2.0,
              ),
            ),
          ),
          if (_statusMessage != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _statusMessage!,
                style: const TextStyle(fontSize: 16, color: Colors.blueGrey),
                textAlign: TextAlign.center,
              ),
            ),
          if (_currentInstruction != null)
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text(
                _currentInstruction!.text,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
              child: ClipRect(
                child: TrailView(
                  map: wiring.map,
                  route: _route,
                  position: _position,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.file_open),
              label: const Text('Pick .jsonl trace to Replay'),
              onPressed: _isPlaying ? null : _pickFile,
            ),
          ),
        ],
      ),
    );
  }
}
