import 'package:flutter/material.dart';

import '../design/design.dart';

/// The standard page header (§ 3.16): an optional uppercase brand-tinted
/// eyebrow, a 24px semibold title, an optional supporting description capped at
/// `max-w-2xl`, and an optional action cluster.
///
/// The web puts actions on the right from `sm` up and stacks them below on a
/// phone. Flutter builds the phone column, so they always stack.
class SrPageHeader extends StatelessWidget {
  const SrPageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.description,
    this.actions = const <Widget>[],
  });

  final String title;

  /// Rendered uppercase in the brand colour.
  final String? eyebrow;

  final String? description;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (eyebrow != null) ...<Widget>[
          Text(
            eyebrow!.toUpperCase(),
            style: SrTypography.eyebrow.copyWith(color: sr.brand),
          ),
          const SizedBox(height: SrSpacing.xs),
        ],
        Text(
          title,
          style: SrTypography.pageTitle.copyWith(color: sr.foreground),
        ),
        if (description != null) ...<Widget>[
          const SizedBox(height: SrSpacing.xsPlus),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: SrSpacing.formMaxWidth),
            child: Text(
              description!,
              style: SrTypography.body.copyWith(color: sr.textSecondary),
            ),
          ),
        ],
        if (actions.isNotEmpty) ...<Widget>[
          const SizedBox(height: SrSpacing.lg),
          Wrap(
            spacing: SrSpacing.sm,
            runSpacing: SrSpacing.sm,
            children: actions,
          ),
        ],
      ],
    );
  }
}

/// A within-page section heading (§ 3.16): 18px semibold title, optional
/// description, optional right-aligned action.
class SrSectionHeader extends StatelessWidget {
  const SrSectionHeader({
    super.key,
    required this.title,
    this.description,
    this.action,
  });

  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: SrTypography.sectionTitle.copyWith(color: sr.foreground),
              ),
              if (description != null) ...<Widget>[
                const SizedBox(height: SrSpacing.xxs),
                Text(
                  description!,
                  style: SrTypography.body.copyWith(color: sr.textSecondary),
                ),
              ],
            ],
          ),
        ),
        if (action != null) ...<Widget>[
          const SizedBox(width: SrSpacing.lg),
          action!,
        ],
      ],
    );
  }
}

/// The standard page body: the page gutter, and a max width so a card does not
/// stretch across a tablet or a desktop browser.
///
/// `px-4 py-6` on a phone (§ 2.9), widening to `px-6` at `sm`, capped at
/// `max-w-6xl` — the same responsive rule the web's `<main>` uses.
class SrPageBody extends StatelessWidget {
  const SrPageBody({
    super.key,
    required this.children,
    this.scrollable = true,
    this.maxWidth = SrSpacing.contentMaxWidth,
  });

  final List<Widget> children;
  final bool scrollable;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final double horizontal = width >= SrSpacing.breakpointSm
        ? SrSpacing.xxl
        : SrSpacing.lg;

    final EdgeInsets gutter = EdgeInsets.symmetric(
      horizontal: horizontal,
      vertical: SrSpacing.xxl,
    );

    final Widget content = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );

    final Widget body = scrollable
        ? SingleChildScrollView(padding: gutter, child: content)
        : Padding(padding: gutter, child: content);

    return _FadeIn(child: body);
  }
}

/// The web's `sr-animate-fade-in`, applied to `<main>` on every route: 220 ms
/// ease-out, opacity 0→1 with a 4px upward settle (§ 2.12).
///
/// A [TweenAnimationBuilder] rather than a controller — it plays once on mount,
/// needs no `State` to dispose, and costs nothing after it settles.
///
/// Under reduced motion the duration collapses to zero, so the content simply
/// appears. The end state is identical either way; only the transition differs.
class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: SrMotion.respects(context) ? SrMotion.medium : Duration.zero,
      curve: SrMotion.standard,
      builder: (BuildContext context, double t, Widget? child) {
        if (t == 1) {
          // Settled: drop the wrappers so nothing composites afterwards.
          return child!;
        }
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 4 * (1 - t)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
