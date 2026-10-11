import 'package:breadcrumb/app/theme.dart';
import 'package:breadcrumb/app/widgets/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
      theme: BreadcrumbTheme.themeData,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('PrimaryButton', () {
    testWidgets('shows the label, is at least 52 dp tall and calls onPressed', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(PrimaryButton(label: 'Go', onPressed: () => taps++)));

      expect(find.widgetWithText(ElevatedButton, 'Go'), findsOneWidget);
      expect(tester.getSize(find.byType(ElevatedButton)).height,
          greaterThanOrEqualTo(BreadcrumbTheme.minTouch));

      await tester.tap(find.text('Go'));
      expect(taps, 1);
    });

    testWidgets('while busy it is disabled and shows the thinking label', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(
        PrimaryButton(label: 'Go', busy: true, onPressed: () => taps++),
      ));

      expect(find.text('Go'), findsNothing);
      expect(find.text('Thinking...'), findsOneWidget);
      expect(find.byType(ThinkingIndicator), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);

      await tester.tap(find.byType(ElevatedButton));
      expect(taps, 0);
    });

    testWidgets('a null onPressed disables it', (tester) async {
      await tester.pumpWidget(_host(const PrimaryButton(label: 'Go', onPressed: null)));
      expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);
    });
  });

  group('ActionCard', () {
    testWidgets('shows icon, title and subtitle and calls onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(ActionCard(
        icon: Icons.navigation_rounded,
        title: 'Navigate',
        subtitle: 'Follow the trail',
        onTap: () => taps++,
      )));

      expect(find.byIcon(Icons.navigation_rounded), findsOneWidget);
      expect(find.text('Navigate'), findsOneWidget);
      expect(find.text('Follow the trail'), findsOneWidget);
      expect(tester.getSize(find.byType(ActionCard)).height,
          greaterThanOrEqualTo(BreadcrumbTheme.minTouch));

      await tester.tap(find.text('Navigate'));
      expect(taps, 1);
    });

    testWidgets('is announced as a button', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(ActionCard(
        icon: Icons.navigation_rounded,
        title: 'Navigate',
        subtitle: 'Follow the trail',
        onTap: () {},
      )));

      expect(
        tester.getSemantics(find.byType(ActionCard)),
        matchesSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
          label: 'Navigate\nFollow the trail',
        ),
      );
      handle.dispose();
    });
  });

  group('StatusPill', () {
    testWidgets('named pills carry the agreed labels', (tester) async {
      await tester.pumpWidget(_host(const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusPill.offline(),
          StatusPill.aiOnDevice(),
          StatusPill.simulated(),
        ],
      )));

      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('AI on-device'), findsOneWidget);
      expect(find.text('SIMULATED'), findsOneWidget);
    });

    testWidgets('SIMULATED is amber', (tester) async {
      await tester.pumpWidget(_host(const StatusPill.simulated()));
      final text = tester.widget<Text>(find.text('SIMULATED'));
      expect(text.style?.color, BreadcrumbTheme.warning);
    });

    testWidgets('AI on-device is bright when ready and grey while warming', (tester) async {
      await tester.pumpWidget(_host(const StatusPill.aiOnDevice(ready: true)));
      expect(tester.widget<Text>(find.text('AI on-device')).style?.color, BreadcrumbTheme.textPrimary);

      await tester.pumpWidget(_host(const StatusPill.aiOnDevice(ready: false)));
      expect(tester.widget<Text>(find.text('AI on-device')).style?.color,
          BreadcrumbTheme.textSecondary);
    });
  });

  group('SectionHeader', () {
    testWidgets('shows the title and the trailing text', (tester) async {
      await tester.pumpWidget(_host(const SectionHeader('Marked places', trailing: '3 places')));
      expect(find.text('Marked places'), findsOneWidget);
      expect(find.text('3 places'), findsOneWidget);
    });

    testWidgets('trailing text is optional', (tester) async {
      await tester.pumpWidget(_host(const SectionHeader('Start')));
      expect(find.text('Start'), findsOneWidget);
    });
  });

  group('ThinkingIndicator', () {
    testWidgets('shows three dots and the label, and the dots animate', (tester) async {
      await tester.pumpWidget(_host(const ThinkingIndicator(label: 'Thinking...')));

      expect(find.text('Thinking...'), findsOneWidget);
      final dots = find.descendant(
        of: find.byType(ThinkingIndicator),
        matching: find.byType(Opacity),
      );
      expect(dots, findsNWidgets(3));

      final before = tester.widget<Opacity>(dots.first).opacity;
      await tester.pump(const Duration(milliseconds: 400));
      final after = tester.widget<Opacity>(dots.first).opacity;
      expect(after, isNot(before));
    });

    testWidgets('stays still when system animations are off', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: BreadcrumbTheme.themeData,
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: ThinkingIndicator()),
        ),
      ));

      // Settles, so no repeating animation is running.
      await tester.pumpAndSettle();
      expect(find.byType(ThinkingIndicator), findsOneWidget);
    });
  });

  testWidgets('the app theme is dark with the agreed colours and 52 dp targets', (tester) async {
    final theme = BreadcrumbTheme.themeData;
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, const Color(0xFF0E1116));
    expect(theme.colorScheme.surface, const Color(0xFF161B22));
    expect(theme.colorScheme.primary, const Color(0xFF2DE2C3));
    expect(BreadcrumbTheme.warning, const Color(0xFFFFB020));
    expect(BreadcrumbTheme.textPrimary, const Color(0xFFF2F5F7));
    expect(BreadcrumbTheme.textSecondary, const Color(0xFF8B949E));
    expect(BreadcrumbTheme.radius, 14);
    expect(theme.textTheme.displayLarge?.fontSize, greaterThanOrEqualTo(32));
    expect(theme.textTheme.headlineMedium?.fontSize, 24);
    expect(theme.textTheme.bodyMedium?.fontSize, 16);
    // Inter is bundled, nothing is downloaded.
    expect(theme.textTheme.bodyMedium?.fontFamily, anyOf(isNull, 'Roboto', 'Inter'));
    expect(
      theme.elevatedButtonTheme.style?.minimumSize?.resolve({}),
      const Size(BreadcrumbTheme.minTouch, BreadcrumbTheme.minTouch),
    );
  });
}
