import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// True when the system asks for reduced motion; every animation here checks it.
bool calm(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

const ease = Cubic(0.2, 0.8, 0.2, 1); // quick start, soft landing

/// Fades and rises into place after [delay]. Used to stagger cards in.
class Appear extends StatefulWidget {
  const Appear({super.key, required this.child, this.delay = Duration.zero, this.offset = 14});

  final Widget child;
  final Duration delay;
  final double offset;

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 620));
  Timer? _t;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted || _t != null) return;
    if (calm(context)) {
      _c.value = 1;
    } else {
      _t = Timer(widget.delay, () => mounted ? _c.forward() : null);
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = CurvedAnimation(parent: _c, curve: ease);
    return AnimatedBuilder(
      animation: a,
      builder: (_, child) => Opacity(
        opacity: a.value,
        child: Transform.translate(offset: Offset(0, widget.offset * (1 - a.value)), child: child),
      ),
      child: widget.child,
    );
  }
}

/// Animates a number from its last value to the new one.
class CountUp extends StatelessWidget {
  const CountUp({super.key, required this.value, required this.format, required this.style});

  final double value;
  final String Function(double) format;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: calm(context) ? Duration.zero : const Duration(milliseconds: 1100),
      curve: ease,
      builder: (_, v, __) => Text(format(v), style: style),
    );
  }
}

/// A soft repeating pulse, for things that want attention without shouting.
class Pulse extends StatefulWidget {
  const Pulse({super.key, required this.builder, this.period = const Duration(milliseconds: 1800)});

  /// Called with a value that eases 0 -> 1 -> 0 each period.
  final Widget Function(BuildContext, double) builder;
  final Duration period;

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (calm(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => widget.builder(context, (1 - math.cos(_c.value * 2 * math.pi)) / 2),
      );
}

/// A live dot: solid centre with a ring that breathes outward.
class LiveDot extends StatelessWidget {
  const LiveDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size * 2.6,
      child: Pulse(
        builder: (_, t) => Stack(alignment: Alignment.center, children: [
          Container(
            width: size * (1 + 1.6 * t),
            height: size * (1 + 1.6 * t),
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.28 * (1 - t))),
          ),
          Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        ]),
      ),
    );
  }
}

/// Lifts slightly and tints on hover, so rows and cards feel touchable.
class Hoverable extends StatefulWidget {
  const Hoverable({super.key, required this.builder});

  final Widget Function(BuildContext, bool hovered) builder;

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _h = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _h = true),
        onExit: (_) => setState(() => _h = false),
        child: widget.builder(context, _h),
      );
}

/// Spins its child while [spinning], settling smoothly when it stops.
class Spin extends StatefulWidget {
  const Spin({super.key, required this.spinning, required this.child});

  final bool spinning;
  final Widget child;

  @override
  State<Spin> createState() => _SpinState();
}

class _SpinState extends State<Spin> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didUpdateWidget(Spin old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() {
    if (widget.spinning && !calm(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else if (_c.isAnimating) {
      _c.animateTo(1, duration: Duration(milliseconds: ((1 - _c.value) * 600).round())).then((_) => _c.value = 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(turns: _c, child: widget.child);
}
