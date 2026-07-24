import 'package:flutter/material.dart';

import '../design/design.dart';

/// The card variants, from § 3.5 of `docs/mobile-ui-design-handoff.md`.
enum SrCardVariant {
  /// The resting surface: hairline border, `shadow-card`.
  standard,

  /// Tappable. The web lifts 2px and tints the border indigo on hover; on
  /// mobile that becomes a press state.
  interactive,

  /// Featured: brand-tinted border plus a 1px inner ring.
  highlighted,

  /// Recessed: muted fill, **no shadow**.
  muted,
}

/// The single definition of a card: a 16-radius surface with a 1px hairline and
/// the layered `shadow-card`.
///
/// The shadow is painted here rather than delegated to Material elevation.
/// Material produces one tinted blur; the product's card shadow is two
/// low-opacity stops tinted slate-900 (black in dark), and that layering is what
/// reads as "premium" instead of "Material default".
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

  /// When set the card becomes tappable. Pair with [SrCardVariant.interactive]
  /// to take the press treatment too.
  final VoidCallback? onTap;

  /// `p-5` — the padding every content card uses on a phone.
  static const EdgeInsets defaultPadding = EdgeInsets.all(SrSpacing.xl);

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final BorderRadius radius = BorderRadius.circular(SrRadii.surface);

    final Color background = switch (variant) {
      SrCardVariant.muted => sr.surfaceMuted,
      _ => sr.surface,
    };
    final Color borderColor = switch (variant) {
      SrCardVariant.highlighted =>
        sr.brandSoft == sr.surface
            ? sr.border
            : sr.onBrandSoft.withValues(alpha: 0.35),
      _ => sr.border,
    };
    final List<BoxShadow> shadow = switch (variant) {
      SrCardVariant.muted => const <BoxShadow>[],
      _ => sr.cardShadow,
    };

    Widget content = Padding(padding: padding ?? defaultPadding, child: child);

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          splashColor: sr.brandSoft,
          highlightColor: sr.brandSoft,
          child: content,
        ),
      );
    }

    return AnimatedContainer(
      duration: SrMotion.fast,
      curve: SrMotion.standard,
      decoration: BoxDecoration(
        color: background,
        borderRadius: radius,
        border: Border.all(color: borderColor),
        boxShadow: shadow,
      ),
      foregroundDecoration: variant == SrCardVariant.highlighted
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: sr.brandSoft),
            )
          : null,
      child: ClipRRect(borderRadius: radius, child: content),
    );
  }
}

/// A section card: a 16px semibold title, an optional supporting description, an
/// optional right-aligned action, and a body 20px below.
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
    final SrColorScheme sr = context.sr;

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
                    Text(
                      title,
                      style: SrTypography.cardTitle.copyWith(
                        color: sr.foreground,
                      ),
                    ),
                    if (description != null) ...<Widget>[
                      const SizedBox(height: SrSpacing.xs),
                      Text(
                        description!,
                        style: SrTypography.body.copyWith(
                          color: sr.textSecondary,
                        ),
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
          ),
          const SizedBox(height: SrSpacing.xl),
          child,
        ],
      ),
    );
  }
}

/// A tinted, rounded icon disc — the recurring motif in front of a status
/// heading, an empty state, or an access-denied message (§ 2.10).
///
/// Sizes in use: 40 (`rounded-xl`, stat and detail cards), 44 (status card, form
/// step), 48 (invitation, upload), 56 (empty state, access denied).
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
  final double size;

  /// Adds the 1px inset ring the access-denied and invitation discs carry.
  final bool ringed;

  /// The web pairs a 40px disc with a 20px glyph and a 56px disc with 24–28px.
  double get _glyphSize => size <= 40 ? 20 : (size <= 48 ? 24 : 28);

  @override
  Widget build(BuildContext context) {
    final SrToneColors colors = context.sr.tone(tone);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.fill,
        // 40px discs take the control radius; larger discs take the surface
        // radius, per § 2.10.
        borderRadius: BorderRadius.circular(
          size <= 40 ? SrRadii.control : SrRadii.surface,
        ),
        border: ringed ? Border.all(color: colors.discFill) : null,
      ),
      child: Icon(icon, color: colors.foreground, size: _glyphSize),
    );
  }
}
