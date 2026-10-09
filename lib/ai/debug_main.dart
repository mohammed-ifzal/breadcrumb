/// Entry point for the Gemma spike: `flutter run -t lib/ai/debug_main.dart`.
library;

import 'package:flutter/material.dart';

import 'debug_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(title: 'Gemma debug', home: GemmaDebugScreen()));
}
