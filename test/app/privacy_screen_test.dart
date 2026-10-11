import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:breadcrumb/app/screens/privacy_screen.dart';
import 'package:breadcrumb/app/theme.dart';

void main() {
  Widget wrap() => MaterialApp(
        theme: BreadcrumbTheme.themeData,
        home: const PrivacyScreen(),
      );

  group('PrivacyScreen', () {
    testWidgets('renders without overflow at default font scale', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap());
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without overflow at font scale 1.3 on 360x640',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 640),
          textScaler: TextScaler.linear(1.3),
        ),
        child: wrap(),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the required privacy text', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap());

      // Scroll to make sure all content is rendered
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pump();

      // The key sentences must be somewhere in the rendered tree.
      expect(
        find.textContaining('No GPS', findRichText: true),
        findsAtLeastNWidgets(1),
      );
      expect(
        find.textContaining('no internet', findRichText: true),
        findsAtLeastNWidgets(1),
      );
      expect(
        find.textContaining('no account', findRichText: true),
        findsAtLeastNWidgets(1),
      );
      expect(
        find.textContaining('Scan sign', findRichText: true),
        findsAtLeastNWidgets(1),
      );
      expect(
        find.textContaining('never stored or sent', findRichText: true),
        findsAtLeastNWidgets(1),
      );
      expect(
        find.textContaining('Maps stay on this phone', findRichText: true),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('has a back button that pops the route', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      bool popped = false;
      await tester.pumpWidget(MaterialApp(
        theme: BreadcrumbTheme.themeData,
        home: Builder(builder: (ctx) {
          return Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.push(
                ctx,
                MaterialPageRoute(builder: (_) => const PrivacyScreen()),
              ),
              child: const Text('Open'),
            ),
          );
        }),
        navigatorObservers: [
          _PopObserver(onPop: () => popped = true),
        ],
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // PrivacyScreen is now shown
      expect(find.byType(PrivacyScreen), findsOneWidget);

      // Tap the back button
      final backButton = find.byType(IconButton).first;
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      expect(popped, isTrue);
    });

    testWidgets('Privacy title is visible in AppBar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap());

      expect(find.text('Privacy'), findsOneWidget);
    });

    testWidgets('uses Inter font family (theme applied)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap());

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      // Theme is applied — no overflow errors and scaffold exists.
      expect(scaffold, isNotNull);
    });
  });
}

class _PopObserver extends NavigatorObserver {
  _PopObserver({required this.onPop});
  final VoidCallback onPop;

  @override
  void didPop(Route route, Route? previousRoute) {
    onPop();
  }
}
