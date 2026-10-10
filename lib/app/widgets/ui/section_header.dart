import 'package:flutter/material.dart';

import '../../theme.dart';

/// An uppercase label above a group, with optional text on the right
/// (for example "3 places").
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(title.toUpperCase(), style: BreadcrumbTheme.label),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              Text(
                trailing,
                style: BreadcrumbTheme.label.copyWith(color: BreadcrumbTheme.accent),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
