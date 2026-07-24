import 'package:flutter/material.dart';

import '../design/design.dart';

/// The standard page header, translated from `PageHeader` in the web
/// application's `components/ui/page-header.tsx`.
///
/// An optional eyebrow, a title, an optional supporting description, and an
/// optional action cluster. The web places actions to the right on wide screens;
/// on mobile they always wrap beneath the text, because a title plus a button on
/// one 360px row leaves room for neither.
class SrPageHeader extends StatelessWidget {
  const SrPageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.description,
    this.actions = const <Widget>[],
  });

  final String title;

  /// Rendered uppercase in the brand color, exactly as on the web.
  final String? eyebrow;

  final String? description;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (eyebrow != null) ...<Widget>[
          Text(eyebrow!.toUpperCase(), style: SrTypography.eyebrow),
          const SizedBox(height: SrSpacing.xs),
        ],
        Text(title, style: SrTypography.pageTitle),
        if (description != null) ...<Widget>[
          const SizedBox(height: SrSpacing.xsPlus),
          Text(description!, style: SrTypography.bodyMuted),
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

/// A lighter within-page section heading, for grouping content under a page
/// header. Mirrors `SectionHeader` in `page-header.tsx`.
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: SrTypography.sectionTitle),
              if (description != null) ...<Widget>[
                const SizedBox(height: SrSpacing.xxs),
                Text(description!, style: SrTypography.bodyMuted),
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

/// The standard page body: the app background, the page gutter, and a max width
/// so a card does not stretch to 1400px on a tablet or on Flutter web and stop
/// resembling the product.
class SrPageBody extends StatelessWidget {
  const SrPageBody({super.key, required this.children, this.scrollable = true});

  final List<Widget> children;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final Widget content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: SrSpacing.contentMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );

    const EdgeInsets gutter = EdgeInsets.symmetric(
      horizontal: SrSpacing.lg,
      vertical: SrSpacing.xl,
    );

    if (!scrollable) {
      return Padding(padding: gutter, child: content);
    }

    return SingleChildScrollView(padding: gutter, child: content);
  }
}
