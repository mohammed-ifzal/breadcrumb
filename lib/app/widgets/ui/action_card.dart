import 'package:flutter/material.dart';

import '../../theme.dart';

/// A list row: icon, title, caption and a chevron. Flat surface, 1 px border.
/// [highlighted] is kept for callers but no longer changes the look: the
/// accent colour is reserved for the route, the primary button and the
/// instruction card.
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
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: Material(
        color: BreadcrumbTheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BreadcrumbTheme.borderRadius,
          side: BorderSide(color: BreadcrumbTheme.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: BreadcrumbTheme.minTouch),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: BreadcrumbTheme.surfaceRaised,
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                    child: Icon(icon, size: 22, color: BreadcrumbTheme.textPrimary),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: BreadcrumbTheme.body.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(subtitle, style: BreadcrumbTheme.caption),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: BreadcrumbTheme.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
