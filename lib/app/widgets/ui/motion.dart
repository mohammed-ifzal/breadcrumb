import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../trail_view.dart';

/// Endless animations (pulses, listening bars) run only in the app: widget
/// tests can't settle while they loop, and the system "remove animations"
/// setting stops them.
bool loopingAnimations(BuildContext context) =>
    TrailView.defaultAnimate && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

/// Three accent bars that bounce while the microphone is listening.
class ListeningBars extends StatefulWidget {
  const ListeningBars({super.key, this.color = BreadcrumbTheme.accent, this.height = 22});

  final Color color;
  final double height;

  @override
  State<ListeningBars> createState() => _ListeningBarsState();
}

class _ListeningBarsState extends State<ListeningBars> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loopingAnimations(context)) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _heightFor(int bar) {
    final phase = (_controller.value + bar * 0.22) % 1.0;
    return 0.35 + 0.65 * (0.5 + 0.5 * math.sin(phase * 2 * math.pi));
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Listening',
      child: SizedBox(
        width: 22,
        height: widget.height,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 4,
                  height: widget.height * _heightFor(i),
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: const BorderRadius.all(Radius.circular(2)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dot that pulses while [active] (the recording light). Still when not.
class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key, required this.color, this.active = true, this.size = 10});

  final Color color;
  final bool active;
  final double size;

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  void _sync() {
    if (widget.active && loopingAnimations(context)) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PulsingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 2.4,
      height: s * 2.4,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (_controller.isAnimating)
                Container(
                  width: s + s * 1.4 * t,
                  height: s + s * 1.4 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.45 * (1 - t)),
                  ),
                ),
              Container(
                width: s,
                height: s,
                decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
              ),
            ],
          );
        },
      ),
    );
  }
}
