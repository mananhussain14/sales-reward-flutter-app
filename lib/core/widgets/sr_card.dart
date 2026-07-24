import 'package:flutter/material.dart';

import '../design/design.dart';

/// The card variants, mirroring `CARD_VARIANTS` in the web application's
/// `components/ui/card.tsx`.
enum SrCardVariant {
  /// `border-slate-200` — the resting surface.
  standard,

  /// `hover:border-indigo-300 hover:shadow-elevated` — a tappable card. On
  /// mobile the lift is expressed as a press state rather than a hover.
  interactive,

  /// `border-indigo-200 ring-1 ring-indigo-100` — a featured surface.
  highlighted,

  /// `bg-slate-50 shadow-none` — a recessed surface.
  muted,
}

/// The single definition of a "card": a white 16px-radius surface with a slate
/// hairline border and the soft two-stop `--shadow-card`.
///
/// The shadow is painted here rather than delegated to Material elevation,
/// because Material's elevation model produces a single tinted shadow and would
/// lose the layered recipe that gives the product its light, premium weight.
class SrCard extends StatelessWidget {
  const SrCard({
    super.key,
    required this.child,
    this.variant = SrCardVariant.standard,
    this.padding,
    this.onTap,
  });

  final Widget child;
  final SrCardVariant variant;
  final EdgeInsetsGeometry? padding;

  /// When set, the card becomes tappable. Pass [SrCardVariant.interactive] to
  /// also take the hover/press treatment the web uses for clickable cards.
  final VoidCallback? onTap;

  /// `p-5 sm:p-6` — the padding every content card uses.
  static const EdgeInsets defaultPadding = EdgeInsets.all(SrSpacing.xl);

  Color get _background => switch (variant) {
    SrCardVariant.muted => SrColors.appBackground,
    _ => SrColors.surface,
  };

  Color get _border => switch (variant) {
    SrCardVariant.highlighted => SrColors.indigo200,
    _ => SrColors.border,
  };

  List<BoxShadow> get _shadow => switch (variant) {
    SrCardVariant.muted => const <BoxShadow>[],
    _ => SrShadows.card,
  };

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(SrRadii.xl);

    Widget content = Padding(padding: padding ?? defaultPadding, child: child);

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          splashColor: SrColors.brandSoft,
          highlightColor: SrColors.brandSoft,
          child: content,
        ),
      );
    }

    return AnimatedContainer(
      duration: SrMotion.fast,
      curve: SrMotion.standard,
      decoration: BoxDecoration(
        color: _background,
        borderRadius: radius,
        border: Border.all(color: _border),
        boxShadow: _shadow,
      ),
      // `ring-1 ring-indigo-100` on the highlighted variant.
      foregroundDecoration: variant == SrCardVariant.highlighted
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: SrColors.indigo100),
            )
          : null,
      child: ClipRRect(borderRadius: radius, child: content),
    );
  }
}

/// A section card with a title, an optional description and a body — the grouped
/// panel used throughout the web product's forms and detail pages
/// (`SectionCard` in `card.tsx`).
class SrSectionCard extends StatelessWidget {
  const SrSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.description,
    this.action,
  });

  final String title;
  final String? description;
  final Widget? action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: SrTypography.cardTitle),
                    if (description != null) ...<Widget>[
                      const SizedBox(height: SrSpacing.xs),
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
          ),
          const SizedBox(height: SrSpacing.xl),
          child,
        ],
      ),
    );
  }
}

/// A tinted, rounded icon disc — the recurring motif in front of a status
/// heading, an empty state, or an access-denied message.
///
/// Mirrors the `DISC_TONES` treatment shared by `empty-state.tsx` and
/// `status-card.tsx`.
class SrIconDisc extends StatelessWidget {
  const SrIconDisc({
    super.key,
    required this.icon,
    this.tone = SrTone.slate,
    this.size = 56,
    this.ringed = false,
  });

  final IconData icon;
  final SrTone tone;

  /// `h-14 w-14` (56) for empty states, `h-11 w-11` (44) inside a status card.
  final double size;

  /// Adds the `ring-1 ring-inset` outline the access-denied disc carries.
  final bool ringed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(SrRadii.xl),
        border: ringed ? Border.all(color: tone.discBackground) : null,
      ),
      child: Icon(icon, color: tone.foreground, size: size * 0.5),
    );
  }
}
