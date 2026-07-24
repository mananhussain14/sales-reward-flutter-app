import 'package:flutter/material.dart';

import '../design/design.dart';
import 'sr_card.dart';

/// A shimmering loading placeholder (§ 3.11).
///
/// A `slate-200` block (slate-800 in dark) at the 6px skeleton radius, with a
/// 1.4s left-to-right white sweep.
///
/// **Reduced motion removes the sweep, never the block.** The web suppresses
/// `.sr-skeleton::after` entirely under `prefers-reduced-motion` while keeping
/// the surface — the placeholder still says "loading" without moving.
class SrSkeleton extends StatefulWidget {
  const SrSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = SrRadii.skeleton,
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
    final SrColorScheme sr = context.sr;

    final Widget block = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: sr.skeletonBase,
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
    );

    if (!SrMotion.respects(context)) {
      return block;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          // `translateX(-100%)` → `translateX(100%)`, as the CSS keyframe does.
          final double shift = (_controller.value * 2) - 1;
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (Rect bounds) => LinearGradient(
              begin: Alignment(shift - 1, 0),
              end: Alignment(shift + 1, 0),
              colors: <Color>[
                Colors.transparent,
                sr.skeletonHighlight,
                Colors.transparent,
              ],
            ).createShader(bounds),
            child: child!,
          );
        },
        child: block,
      ),
    );
  }
}

/// The skeleton shape for a page header: a title bar and a description bar.
class SrSkeletonPageHeader extends StatelessWidget {
  const SrSkeletonPageHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SrSkeleton(width: 176, height: 28),
        SizedBox(height: SrSpacing.md),
        SrSkeleton(width: 288, height: 16),
      ],
    );
  }
}

/// The skeleton shape for a stat or content card.
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

/// The stat grid's skeleton — one column on a phone, per § 4.5.
class SrSkeletonStatGrid extends StatelessWidget {
  const SrSkeletonStatGrid({super.key, this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (int i = 0; i < count; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: SrSpacing.lg),
          const SrSkeletonCard(),
        ],
      ],
    );
  }
}

/// The skeleton for a card list — the mobile translation of `SkeletonTable`,
/// since a table never renders on a phone (§ 4.2).
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
                  SrSkeleton(
                    width: 40,
                    height: 40,
                    borderRadius: SrRadii.control,
                  ),
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

/// The accessibility wrapper every loading surface goes through.
///
/// Mirrors `SkeletonScreen`: the region announces a **generic** busy label while
/// the visual blocks are hidden from assistive technology. The label is
/// deliberately generic — it never names a record, an organization or a person,
/// because a loading state must not leak what is being loaded.
class SrSkeletonScreen extends StatelessWidget {
  const SrSkeletonScreen({
    super.key,
    required this.child,
    this.label = 'Loading…',
  });

  final Widget child;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      liveRegion: true,
      container: true,
      child: ExcludeSemantics(child: child),
    );
  }
}

/// The shared loading state for a whole screen.
///
/// **Skeletons, not spinners, are this product's loading language** (§ 3.11): a
/// centred `CircularProgressIndicator` would not read as SalesReward. This
/// composes the page-header and list shapes and wraps them in
/// [SrSkeletonScreen].
///
/// Prefer a skeleton whose shape matches what is arriving; use [rows] and
/// [showHeader] to approximate it.
class SrLoadingView extends StatelessWidget {
  const SrLoadingView({
    super.key,
    this.rows = 3,
    this.showHeader = true,
    this.label = 'Loading…',
  });

  final int rows;
  final bool showHeader;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SrSkeletonScreen(
      label: label,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: SrSpacing.lg,
          vertical: SrSpacing.xxl,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: SrSpacing.contentMaxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (showHeader) ...<Widget>[
                  const SrSkeletonPageHeader(),
                  const SizedBox(height: SrSpacing.xxl),
                ],
                SrSkeletonList(rows: rows),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
