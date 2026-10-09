import 'package:flutter/material.dart';
import 'app/screens/permissions_screen.dart';

void main() => runApp(const BreadcrumbApp());

class BreadcrumbApp extends StatelessWidget {
  const BreadcrumbApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Breadcrumb',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const PermissionsScreen(),
    );
  }
}
