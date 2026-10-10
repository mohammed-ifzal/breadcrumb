import 'package:flutter/material.dart';
import 'app/screens/permissions_screen.dart';
import 'app/theme.dart';

void main() => runApp(const BreadcrumbApp());

class BreadcrumbApp extends StatelessWidget {
  const BreadcrumbApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Breadcrumb',
      theme: BreadcrumbTheme.themeData,
      home: const PermissionsScreen(),
    );
  }
}
