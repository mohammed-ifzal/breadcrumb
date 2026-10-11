import 'map_screen.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/ui/ui.dart';
import '../wiring.dart';
import 'package:breadcrumb/ai/device_tier.dart' show basicMatchingLabel;
import 'destination_list_screen.dart';
import 'record_screen.dart';
import 'privacy_screen.dart';
import 'saved_maps_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Load latest recorded map if available (D22)
    Wiring.instance.reloadActiveMap();
    // Warm Gemma AI in background
    Wiring.instance.warmAi();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            BreadcrumbTheme.screenPadding,
            24,
            BreadcrumbTheme.screenPadding,
            24,
          ),
          children: [
            const _Wordmark(),
            const SizedBox(height: 8),
            const Text(
              'Find your way back. No GPS, no internet.',
              style: BreadcrumbTheme.bodySecondary,
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<AiStatus>(
              valueListenable: Wiring.instance.aiStatus,
              builder: (context, status, _) => Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const StatusPill.offline(),
                  if (status.isReady)
                    const StatusPill.aiOnDevice(ready: true)
                  else if (status.isLoading)
                    const StatusPill.aiOnDevice(ready: false)
                  else ...[
                    const StatusPill(
                      // D30: unavailable is the basic tier (matcher + aliases).
                      label: basicMatchingLabel,
                      icon: Icons.manage_search_rounded,
                      tone: StatusTone.neutral,
                    ),
                    if (status.reason != null && status.reason!.isNotEmpty)
                      Text(
                        status.reason!,
                        style: BreadcrumbTheme.caption,
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 32),
            ActionCard(
              icon: Icons.directions_walk_rounded,
              title: 'Record a trail',
              subtitle: 'Walk it once and mark places. The trail draws as you go.',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RecordScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            ActionCard(
              icon: Icons.navigation_outlined,
              title: 'Navigate',
              subtitle: 'Say or type a place. Follow the arrow back along the trail.',
              onTap: () async {
                await Wiring.instance.reloadActiveMap();
                if (!context.mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        const DestinationListScreen(askStart: true),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            ActionCard(
              icon: Icons.map_outlined,
              title: 'View floor map',
              subtitle: 'Full trail, all marked places and route preview.',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MapScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            ActionCard(
              icon: Icons.folder_open_outlined,
              title: 'Saved maps',
              subtitle: 'Choose which recorded map to use. Rename or delete.',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SavedMapsScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.airplanemode_active_rounded,
                    size: 16, color: BreadcrumbTheme.textSecondary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Works in aeroplane mode. Position comes from steps and turns.',
                    style: BreadcrumbTheme.caption,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Center(
              child: _PrivacyLink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyLink extends StatelessWidget {
  const _PrivacyLink();

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PrivacyScreen()),
      ),
      style: TextButton.styleFrom(
        foregroundColor: BreadcrumbTheme.textSecondary,
        textStyle: const TextStyle(
          fontSize: 13,
          fontFamily: BreadcrumbTheme.fontFamily,
        ),
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      child: const Text('Privacy'),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: 'Breadcrumb',
      child: ExcludeSemantics(
        child: Row(
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CustomPaint(painter: _CrumbsPainter()),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Breadcrumb',
                style: BreadcrumbTheme.display,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The logo: a dotted trail ending in a solid dot, in neutral white.
class _CrumbsPainter extends CustomPainter {
  const _CrumbsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = BreadcrumbTheme.textPrimary.withValues(alpha: 0.4);
    final bright = Paint()..color = BreadcrumbTheme.textPrimary;
    final w = size.width;
    final h = size.height;
    canvas.drawCircle(Offset(w * 0.18, h * 0.82), 2, dim);
    canvas.drawCircle(Offset(w * 0.40, h * 0.60), 2, dim);
    canvas.drawCircle(Offset(w * 0.60, h * 0.42), 2.5, dim);
    canvas.drawCircle(Offset(w * 0.82, h * 0.20), 4, bright);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
