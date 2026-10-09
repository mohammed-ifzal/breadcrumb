import 'package:breadcrumb/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app starts', (tester) async {
    await tester.pumpWidget(const BreadcrumbApp());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
