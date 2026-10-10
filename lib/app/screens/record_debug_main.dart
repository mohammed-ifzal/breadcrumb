import 'package:flutter/material.dart';

import 'record_screen.dart';

/// Standalone phone harness. Grant ACTIVITY_RECOGNITION externally with adb.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RecordDebugApp());
}

class RecordDebugApp extends StatelessWidget {
  const RecordDebugApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Breadcrumb record debug',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    home: const RecordScreen(),
  );
}
