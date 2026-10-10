import 'map_screen.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/ui/ui.dart';
import '../wiring.dart';
import 'destination_list_screen.dart';
import 'record_screen.dart';

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
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            const SizedBox(height: 8),
            const _Wordmark(),
            const SizedBox(height: 14),
            const Text(
              'Find your way back. No GPS, no internet.',
              style: TextStyle(fontSize: 20, height: 1.35, color: BreadcrumbTheme.textSecondary),
            ),
            const SizedBox(height: 20),
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
                      label: 'AI unavailable',
                      icon: Icons.cloud_off_rounded,
                      tone: StatusTone.warning,
                    ),
                    if (status.reason != null && status.reason!.isNotEmpty)
                      Text(
                        status.reason!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: BreadcrumbTheme.textSecondary,
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 36),
            const SectionHeader('Start'),
            ActionCard(
              icon: Icons.navigation_rounded,
              title: 'Navigate',
              subtitle: 'Say or type a place. Follow the arrow back along the trail.',
              highlighted: true,
              onTap: () async {
                await Wiring.instance.reloadActiveMap();
                if (!context.mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DestinationListScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            ActionCard(
              icon: Icons.map_rounded,
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
            const SizedBox(height: 32),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.airplanemode_active_rounded,
                    size: 18, color: BreadcrumbTheme.textFaint),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Works in aeroplane mode. Position comes from steps and turns.',
                    style: TextStyle(fontSize: 15, height: 1.4, color: BreadcrumbTheme.textFaint),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: BreadcrumbTheme.surface,
                borderRadius: const BorderRadius.all(Radius.circular(14)),
                border: Border.all(color: BreadcrumbTheme.border),
                boxShadow: BreadcrumbTheme.accentGlow,
              ),
              child: const CustomPaint(painter: _CrumbsPainter()),
            ),
            const SizedBox(width: 14),
            Flexible(
              child: Text.rich(
                TextSpan(
                  text: 'Breadcrumb',
                  children: [
                    TextSpan(
                      text: '.',
                      style: TextStyle(color: BreadcrumbTheme.accent),
                    ),
                  ],
                ),
                style: BreadcrumbTheme.display,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The logo: a dotted trail ending in a solid dot.
class _CrumbsPainter extends CustomPainter {
  const _CrumbsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = BreadcrumbTheme.accent.withValues(alpha: 0.45);
    final bright = Paint()..color = BreadcrumbTheme.accent;
    final w = size.width;
    final h = size.height;
    canvas.drawCircle(Offset(w * 0.28, h * 0.72), 2.2, dim);
    canvas.drawCircle(Offset(w * 0.42, h * 0.56), 2.2, dim);
    canvas.drawCircle(Offset(w * 0.56, h * 0.44), 2.2, dim);
    canvas.drawCircle(Offset(w * 0.70, h * 0.30), 5, bright);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
