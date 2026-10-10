import 'package:flutter/material.dart';

import '../../theme.dart';

/// A large tappable card: icon tile, title, subtitle and an arrow.
/// [highlighted] gives the recommended action a teal edge and glow.
class ActionCard extends StatelessWidget {
  const ActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final edge = highlighted
        ? BreadcrumbTheme.accent.withValues(alpha: 0.55)
        : BreadcrumbTheme.border;

    return Semantics(
      button: true,
      enabled: onTap != null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BreadcrumbTheme.borderRadius,
          boxShadow: highlighted
              ? [
                  BoxShadow(
                    color: BreadcrumbTheme.accent.withValues(alpha: 0.12),
                    blurRadius: 28,
                  ),
                ]
              : null,
        ),
        child: Material(
          color: BreadcrumbTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BreadcrumbTheme.borderRadius,
            side: BorderSide(color: edge),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: BreadcrumbTheme.minTouch),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: highlighted
                            ? BreadcrumbTheme.accent
                            : BreadcrumbTheme.surfaceRaised,
                        borderRadius: const BorderRadius.all(Radius.circular(16)),
                      ),
                      child: Icon(
                        icon,
                        size: 28,
                        color: highlighted
                            ? BreadcrumbTheme.onAccent
                            : BreadcrumbTheme.accent,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: BreadcrumbTheme.title),
                          const SizedBox(height: 6),
                          Text(subtitle, style: BreadcrumbTheme.bodySecondary),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: highlighted
                            ? BreadcrumbTheme.accent
                            : BreadcrumbTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
