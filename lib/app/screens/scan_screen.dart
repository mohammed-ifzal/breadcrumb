import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/app/wiring.dart';

/// Scan screen implementing Prompt 2:
/// - calls tracker.pauseTurns(true) when it opens and false when it closes
/// - camera preview and capture button
/// - recognised text, then PlaceMatcher result
/// - "You're at `place`" or "Couldn't read that, try again"
/// - if place isn't on route, plans again from it
class ScanScreen extends StatefulWidget {
  const ScanScreen({
    super.key,
    required this.destinationId,
    this.currentRoute,
    this.onReplan,
    this.mockCapture,
  });

  final String destinationId;
  final RoutePlan? currentRoute;
  final void Function(RoutePlan newRoute, Position newPosition)? onReplan;
  final Future<String?> Function()? mockCapture;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  CameraController? _cameraController;
  bool _isCameraReady = false;
  bool _isProcessing = false;
  String? _statusMessage;
  String? _recognizedText;
  Place? _matchedPlace;

  @override
  void initState() {
    super.initState();
    // Prompt 2: call tracker.pauseTurns(true) when it opens
    Wiring.instance.tracker.pauseTurns(true);
    _initializeCamera();
  }

  @override
  void dispose() {
    // Prompt 2: call tracker.pauseTurns(false) when it closes
    Wiring.instance.tracker.pauseTurns(false);
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    if (widget.mockCapture != null) {
      // In test / mock mode
      return;
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _isCameraReady = true;
      });
    } catch (_) {
      // Camera permission refused or unavailable - fallback gracefully
    }
  }

  Future<void> _captureAndScan() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Reading sign...';
      _recognizedText = null;
      _matchedPlace = null;
    });

    try {
      String? imagePath;
      if (widget.mockCapture != null) {
        imagePath = await widget.mockCapture!();
      } else if (_cameraController != null && _cameraController!.value.isInitialized) {
        final file = await _cameraController!.takePicture();
        imagePath = file.path;
      }

      if (imagePath == null) {
        setState(() {
          _isProcessing = false;
          _statusMessage = "Couldn't read that, try again";
        });
        return;
      }

      final wiring = Wiring.instance;
      final reading = await wiring.signReader.read(imagePath);
      final text = reading?.text.trim();

      if (text == null || text.isEmpty) {
        setState(() {
          _isProcessing = false;
          _statusMessage = "Couldn't read that, try again";
        });
        return;
      }

      final match = wiring.matcher.match(text, wiring.map);
      if (match == null) {
        setState(() {
          _isProcessing = false;
          _recognizedText = text;
          _statusMessage = "Couldn't read that, try again";
        });
        return;
      }

      final place = wiring.map.places.cast<Place?>().firstWhere(
        (p) => p?.id == match.placeId,
        orElse: () => null,
      );

      if (place == null) {
        setState(() {
          _isProcessing = false;
          _recognizedText = text;
          _statusMessage = "Couldn't read that, try again";
        });
        return;
      }

      // Check if place is on current route
      final route = widget.currentRoute;
      final isOnRoute = route != null &&
          route.legs.any((leg) {
            final corridor = wiring.map.corridors.cast<Corridor?>().firstWhere(
              (c) => c?.id == leg.corridorId,
              orElse: () => null,
            );
            return corridor != null &&
                (corridor.from == place.id || corridor.to == place.id);
          });

      if (isOnRoute) {
        // Place is on the route: anchor tracker
        final pos = wiring.tracker.anchor(place.id);
        widget.onReplan?.call(route, pos);
      } else {
        // Place is NOT on the route: plan again from it
        final newRoute = wiring.planner.plan(wiring.map, place.id, widget.destinationId);
        wiring.tracker.setRoute(newRoute);
        final pos = wiring.tracker.anchor(place.id);
        widget.onReplan?.call(newRoute, pos);
      }

      setState(() {
        _isProcessing = false;
        _recognizedText = text;
        _matchedPlace = place;
        _statusMessage = "You're at ${place.name}";
      });
    } catch (_) {
      setState(() {
        _isProcessing = false;
        _statusMessage = "Couldn't read that, try again";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Sign'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Container(
                color: Colors.black,
                child: Center(
                  child: _isCameraReady && _cameraController != null
                      ? CameraPreview(_cameraController!)
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt, size: 64, color: Colors.white54),
                            SizedBox(height: 12),
                            Text(
                              'Point camera at a sign',
                              style: TextStyle(color: Colors.white70, fontSize: 18),
                            ),
                          ],
                        ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              color: Colors.black87,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_recognizedText != null) ...[
                    Text(
                      'Recognised: $_recognizedText',
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_statusMessage != null) ...[
                    Text(
                      _statusMessage!,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: _matchedPlace != null ? Colors.greenAccent : Colors.orangeAccent,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_matchedPlace != null) ...[
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 20),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Continue Navigation'),
                    ),
                  ] else ...[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 20),
                      ),
                      onPressed: _isProcessing ? null : _captureAndScan,
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.camera, size: 28),
                      label: Text(_isProcessing ? 'Scanning...' : 'Capture & Read Sign'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
