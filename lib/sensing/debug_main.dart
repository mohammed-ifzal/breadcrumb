import 'package:flutter/material.dart';

import 'debug_screen.dart';
import 'sensing_source.dart';

/// Phone-only sensing harness, independent of the team's production app shell.
/// Grant ACTIVITY_RECOGNITION externally before launching this entry point.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(SensingDebugApp(source: SensingSource()));
}

class SensingDebugApp extends StatelessWidget {
  const SensingDebugApp({super.key, required this.source});

  // SensingDebugScreen owns and disposes this source when its session ends.
  final SensingSource source;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Breadcrumb sensing debug',
    debugShowCheckedModeBanner: false,
    home: SensingDebugScreen(source: source),
  );
}
