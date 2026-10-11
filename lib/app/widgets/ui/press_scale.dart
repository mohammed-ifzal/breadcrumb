import 'package:flutter/material.dart';

import '../../theme.dart';

/// Scales [child] to 0.98 while a pointer is down on it (150 ms). Purely
/// visual: taps still go to the button inside.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child});

  final Widget child;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down && !still ? BreadcrumbTheme.pressScale : 1,
        duration: BreadcrumbTheme.fast,
        curve: BreadcrumbTheme.ease,
        child: widget.child,
      ),
    );
  }
}
