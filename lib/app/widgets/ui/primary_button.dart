import 'package:flutter/material.dart';

import '../../theme.dart';
import 'thinking_indicator.dart';

/// The one main action on a screen: full width, accent, 52 dp tall.
/// While [busy] it is disabled and shows a [ThinkingIndicator] with
/// [busyLabel] instead of [label].
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.busyLabel = 'Thinking...',
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final String busyLabel;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (busy) {
      content = ThinkingIndicator(label: busyLabel);
    } else if (icon != null) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 10),
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      );
    } else {
      content = Text(label, textAlign: TextAlign.center);
    }

    final button = ElevatedButton(
      style: BreadcrumbTheme.primaryButton,
      onPressed: busy ? null : onPressed,
      child: content,
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
