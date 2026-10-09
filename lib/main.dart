import 'package:flutter/material.dart';

// Hour-0 placeholder. Teammate 3 replaces this with the app shell.
void main() => runApp(const BreadcrumbApp());

class BreadcrumbApp extends StatelessWidget {
  const BreadcrumbApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'Breadcrumb',
    home: Scaffold(body: Center(child: Text('Breadcrumb'))),
  );
}
