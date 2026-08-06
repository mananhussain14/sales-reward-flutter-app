/// The application's motion system: four primitives, and nothing else.
///
/// ## Why these live together rather than at their call sites
///
/// A screen that animates by reaching for `AnimatedContainer` here and a
/// `TweenAnimationBuilder` there ends up with six durations, four curves and no
/// way to answer "does this app honour reduced motion?" without reading every
/// widget. These four cover everything the Sales Staff experience animates —
/// content arriving, a number settling, a card acknowledging a press — and every
/// one of them reads [SrMotion.respects] itself.
///
/// ## Reduced motion removes the movement, never the state
///
/// Each primitive collapses to its **settled** end under
/// `MediaQuery.disableAnimations` or `accessibleNavigation`: the content is
/// present and opaque, the number is the real number, the card is at rest. A
/// reader who has asked for less motion sees the same screen, immediately.
///
/// ## Nothing here loops
///
/// Every animation is one-shot and driven by a value change. The only repeating
/// animation in the product remains the skeleton shimmer, which lives on
/// `SrSkeleton` and is removed entirely under reduced motion.
library;

import 'package:flutter/material.dart';

import '../design/design.dart';

/// Content arriving: a 220 ms fade with an 8px rise, played once on mount.
///
/// [index] staggers a list without a timer: the delay is folded into an
/// [Interval] on a single tween, so a card that is rebuilt for an unrelated
/// reason does not restart — a `TweenAnimationBuilder` runs its tween once per
/// *value* change, and the value here never changes.
///
/// The stagger is deliberately capped. Twenty campaigns at 45 ms each would make
/// the last one arrive a second after the first, which reads as a slow screen
/// rather than as a considered one.
class SrEnter extends StatelessWidget {
  const SrEnter({super.key, required this.child, this.index = 0});

  final Widget child;

  /// Position in a list, used only to delay the start.
  final int index;

  /// The per-item stagger step.
  static const Duration step = Duration(milliseconds: 45);

  /// The stagger stops accumulating after this many items.
  static const int maxStaggered = 6;

  @override
  Widget build(BuildContext context) {
    if (!SrMotion.respects(context)) {
      return child;
    }

    final int position = index.clamp(0, maxStaggered);
    final Duration delay = step * position;
    final Duration total = delay + SrMotion.medium;
    final double start = total.inMicroseconds == 0
        ? 0
        : delay.inMicroseconds / total.inMicroseconds;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: SrMotion.standard),
      builder: (BuildContext context, double t, Widget? child) {
        if (t == 1) {
          // Settled: drop the wrappers so nothing composites afterwards.
          return child!;
        }
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - t)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// A whole number counting up to its real value, once.
///
/// ## The animation is a function of the value, not of the build
///
/// The tween restarts only when [value] actually changes. A Bloc that emits an
/// equal state, a theme change, a rotation and a parent rebuild all leave the
/// number exactly where it is — which is the difference between a figure that
/// settles and one that flickers every time anything on the screen moves.
///
/// ## It counts to a stored value and never past it
///
/// [builder] receives an integer on the way to [value] and exactly [value] at
/// the end. Nothing here rounds, projects or extrapolates: the final frame is
/// the number the backend returned.
class SrCountUp extends StatefulWidget {
  const SrCountUp({
    super.key,
    required this.value,
    required this.builder,
    this.duration = const Duration(milliseconds: 650),
  });

  /// The authoritative figure. The animation ends here.
  final int value;

  /// Renders the number. Called with intermediate values while animating.
  final Widget Function(BuildContext context, int displayed) builder;

  final Duration duration;

  @override
  State<SrCountUp> createState() => _SrCountUpState();
}

class _SrCountUpState extends State<SrCountUp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  /// Where the current run started. Zero for the first, then wherever the last
  /// run finished — so a refreshed total slides from the old figure rather than
  /// dropping back to zero.
  int _from = 0;

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Deferred to here rather than initState because the reduced-motion
    // decision needs a MediaQuery, and the first run must respect it.
    if (_started) {
      return;
    }
    _started = true;
    _run();
  }

  @override
  void didUpdateWidget(covariant SrCountUp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) {
      return;
    }
    _from = _displayed(oldWidget.value);
    _run();
  }

  /// The figure currently on screen, given what the previous target was.
  int _displayed(int previousTarget) {
    if (!_controller.isAnimating) {
      return previousTarget;
    }
    return (_from + ((previousTarget - _from) * _controller.value)).round();
  }

  void _run() {
    if (!SrMotion.respects(context)) {
      _from = widget.value;
      _controller.value = 1;
      return;
    }
    _controller
      ..stop()
      ..value = 0
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final int displayed = _controller.value >= 1
            ? widget.value
            : (_from + ((widget.value - _from) * _controller.value)).round();
        return widget.builder(context, displayed);
      },
    );
  }
}

/// A 150 ms press acknowledgement: the surface settles 2% into the page.
///
/// Driven by a raw [Listener] rather than a `GestureDetector`, so it never
/// enters the gesture arena and never competes with the `InkWell` inside the
/// card it wraps. The tap itself stays the child's to handle.
class SrPressScale extends StatefulWidget {
  const SrPressScale({super.key, required this.child, this.enabled = true});

  final Widget child;

  /// False for a surface that is not interactive, so nothing moves under a
  /// stray touch.
  final bool enabled;

  @override
  State<SrPressScale> createState() => _SrPressScaleState();
}

class _SrPressScaleState extends State<SrPressScale> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed == value) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || !SrMotion.respects(context)) {
      return widget.child;
    }

    return Listener(
      // Opaque, so the whole surface acknowledges a press — including the
      // padding and the gaps between a card's children, which is where a thumb
      // usually lands. A `Listener` never consumes an event, so the `InkWell`
      // inside still receives the tap and still owns it.
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: SrMotion.fast,
        curve: SrMotion.standard,
        child: widget.child,
      ),
    );
  }
}

/// A restrained success mark: the disc scales in once and stops.
///
/// Deliberately not a confetti burst, a looping tick or a full-screen takeover.
/// A person who has just submitted a receipt is usually about to submit the
/// next one, and an animation they have to wait out is a cost, not a reward.
class SrSuccessMark extends StatelessWidget {
  const SrSuccessMark({
    super.key,
    this.icon = Icons.check_circle_rounded,
    this.tone = SrTone.emerald,
    this.size = 48,
  });

  final IconData icon;
  final SrTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final SrToneColors colors = context.sr.tone(tone);
    final Widget disc = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(SrRadii.surface),
      ),
      child: Icon(icon, size: size * 0.5, color: colors.foreground),
    );

    if (!SrMotion.respects(context)) {
      return disc;
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      builder: (BuildContext context, double t, Widget? child) =>
          Transform.scale(scale: 0.7 + (0.3 * t), child: child),
      child: disc,
    );
  }
}
