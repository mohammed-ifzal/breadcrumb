import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Three dots that pulse in turn, with an optional label, shown while the
/// on-device AI is working. With animations turned off in system settings
/// the dots stay still.
class ThinkingIndicator extends StatefulWidget {
  const ThinkingIndicator({
    super.key,
    this.label,
    this.color = BreadcrumbTheme.accent,
    this.dotSize = 8,
    this.style,
  });

  final String? label;
  final Color color;
  final double dotSize;
  final TextStyle? style;

  @override
  State<ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _opacityFor(int dot) {
    final phase = (_controller.value - dot * 0.18) % 1.0;
    // A smooth bump that peaks once per cycle.
    return 0.3 + 0.7 * math.max(0.0, math.sin(phase * math.pi));
  }

  @override
  Widget build(BuildContext context) {
    final dots = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : widget.dotSize * 0.6),
              child: Opacity(
                opacity: _opacityFor(i),
                child: Container(
                  width: widget.dotSize,
                  height: widget.dotSize,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    final label = widget.label;
    if (label == null) {
      return Semantics(label: 'Thinking', child: dots);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: dots),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            label,
            style: widget.style,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
