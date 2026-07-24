import 'package:flutter/material.dart';

import '../design/design.dart';
import 'sr_card.dart';

/// A shimmering loading placeholder, translated from the `.sr-skeleton` rule in
/// the web application's `globals.css`.
///
/// A slate-200 block with a white sweep travelling left to right over 1.4s. The
/// web disables the sweep under `prefers-reduced-motion`; this widget honours
/// the platform equivalent, [MediaQuery.disableAnimationsOf], and falls back to
/// a static block — the placeholder still communicates "loading" without motion.
class SrSkeleton extends StatefulWidget {
  const SrSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = SrRadii.sm,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<SrSkeleton> createState() => _SrSkeletonState();
}

class _SrSkeletonState extends State<SrSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SrMotion.shimmer,
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);

    final Widget block = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: SrColors.skeletonBase,
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
    );

    if (reduceMotion) {
      return block;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (Rect bounds) {
              // `translateX(-100%)` → `translateX(100%)`, as the CSS keyframe does.
              final double shift = (_controller.value * 2) - 1;
              return LinearGradient(
                begin: Alignment(shift - 1, 0),
                end: Alignment(shift + 1, 0),
                colors: const <Color>[
                  Colors.transparent,
                  SrColors.skeletonHighlight,
                  Colors.transparent,
                ],
              ).createShader(bounds);
            },
            child: child!,
          );
        },
        child: block,
      ),
    );
  }
}

/// A card-shaped loading placeholder — the shape the web's `loading.tsx` files
/// reuse so a route never flashes a blank screen.
class SrSkeletonCard extends StatelessWidget {
  const SrSkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const SrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SrSkeleton(width: 96, height: 16),
          SizedBox(height: SrSpacing.lg),
          SrSkeleton(width: 64, height: 32),
          SizedBox(height: SrSpacing.md),
          SrSkeleton(width: 128, height: 12),
        ],
      ),
    );
  }
}

/// A list-shaped loading placeholder — the mobile translation of the web's
/// `SkeletonRows`, which stands in for a table.
class SrSkeletonList extends StatelessWidget {
  const SrSkeletonList({super.key, this.rows = 4});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return SrCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < rows; i++) ...<Widget>[
            if (i > 0) const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.all(SrSpacing.lg),
              child: Row(
                children: <Widget>[
                  SrSkeleton(width: 40, height: 40, borderRadius: SrRadii.lg),
                  SizedBox(width: SrSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SrSkeleton(width: 160, height: 14),
                        SizedBox(height: SrSpacing.sm),
                        SrSkeleton(width: 96, height: 12),
                      ],
                    ),
                  ),
                  SizedBox(width: SrSpacing.lg),
                  SrSkeleton(width: 64, height: 24, borderRadius: SrRadii.full),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The shared "this screen is loading" state.
///
/// Prefer a skeleton that matches the shape of what is coming; use this
/// spinner-and-label form only where the incoming shape is not yet known.
class SrLoadingView extends StatelessWidget {
  const SrLoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: message ?? 'Loading',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(SrSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              if (message != null) ...<Widget>[
                const SizedBox(height: SrSpacing.lg),
                Text(
                  message!,
                  style: SrTypography.bodyMuted,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
