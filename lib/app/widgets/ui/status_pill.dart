import 'package:flutter/material.dart';

import '../../theme.dart';

enum StatusTone { neutral, accent, warning }

/// A small rounded status label, such as "Offline" or "SIMULATED".
/// Warning pills are amber: use them for anything that is not real sensing.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.icon,
    this.tone = StatusTone.neutral,
  });

  /// The app makes no network calls at runtime.
  const StatusPill.offline({super.key})
      : label = 'Offline',
        icon = Icons.wifi_off_rounded,
        tone = StatusTone.neutral;

  /// Gemma and speech run on the phone. Teal once the model is loaded.
  const StatusPill.aiOnDevice({super.key, bool ready = true})
      : label = 'AI on-device',
        icon = Icons.memory_rounded,
        tone = ready ? StatusTone.accent : StatusTone.neutral;

  /// Shown whenever steps or turns come from a simulation, not the sensors.
  const StatusPill.simulated({super.key})
      : label = 'SIMULATED',
        icon = Icons.science_outlined,
        tone = StatusTone.warning;

  final String label;
  final IconData? icon;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, Color edge) = switch (tone) {
      StatusTone.neutral => (
          BreadcrumbTheme.textSecondary,
          BreadcrumbTheme.surface,
          BreadcrumbTheme.border,
        ),
      StatusTone.accent => (
          BreadcrumbTheme.accent,
          BreadcrumbTheme.accent.withValues(alpha: 0.08),
          BreadcrumbTheme.accent.withValues(alpha: 0.35),
        ),
      StatusTone.warning => (
          BreadcrumbTheme.warning,
          BreadcrumbTheme.warning.withValues(alpha: 0.10),
          BreadcrumbTheme.warning,
        ),
    };

    return Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        border: Border.all(color: edge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              style: BreadcrumbTheme.label.copyWith(color: fg, letterSpacing: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
