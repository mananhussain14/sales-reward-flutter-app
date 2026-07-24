import 'package:flutter/material.dart';

import '../design/design.dart';

/// The five button variants, from § 3.1 of
/// `docs/mobile-ui-design-handoff.md`.
enum SrButtonVariant { primary, secondary, outline, ghost, danger }

/// The three button sizes.
///
/// `md` (44) and `lg` (48) already clear the 44pt touch-target minimum; the
/// handoff notes explicitly that they must not be shrunk to `sm` on mobile.
enum SrButtonSize {
  /// h-9 / px-3 / 14px.
  sm(height: 36, horizontalPadding: SrSpacing.md),

  /// h-11 / px-4 / 14px — the default.
  md(height: 44, horizontalPadding: SrSpacing.lg),

  /// h-12 / px-5 / 16px — the primary submit on auth and receipt forms.
  lg(height: 48, horizontalPadding: SrSpacing.xl);

  const SrButtonSize({required this.height, required this.horizontalPadding});

  final double height;
  final double horizontalPadding;

  TextStyle get textStyle =>
      this == SrButtonSize.lg ? SrTypography.buttonLarge : SrTypography.button;
}

/// The shared button.
///
/// Carries the product's geometry (12-radius, semibold label, 8px icon gap,
/// `shadow-sm` at rest) and its **built-in loading state**: while [loading] the
/// button disables itself, prepends a 16px spinner and optionally swaps its
/// label. The handoff calls for exactly that rather than a bare
/// `CircularProgressIndicator` replacing the child.
///
/// That behaviour is not only cosmetic. `onboard_vendor_retailer()` has **no
/// server-side idempotency**, so a double submit creates two Retailers;
/// disabling on submit is the client's half of that guard.
///
/// Disabled and loading both render at 60% opacity with the shadow removed,
/// matching § 2.6 — deliberately not Material's default grey.
class SrButton extends StatelessWidget {
  const SrButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = SrButtonVariant.primary,
    this.size = SrButtonSize.md,
    this.icon,
    this.loading = false,
    this.loadingLabel,
    this.fullWidth = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final SrButtonVariant variant;
  final SrButtonSize size;
  final IconData? icon;

  /// Shows the spinner and disables the button.
  final bool loading;

  /// The label shown while [loading] — "Signing in…", "Submitting…". Falls back
  /// to [label].
  final String? loadingLabel;

  final bool fullWidth;

  bool get _enabled => onPressed != null && !loading;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    final (Color fill, Color pressedFill, Color foreground) = switch (variant) {
      SrButtonVariant.primary => (sr.brand, sr.brandHover, sr.onBrand),
      SrButtonVariant.secondary => (
        sr.secondaryFill,
        sr.secondaryHover,
        sr.onSecondary,
      ),
      SrButtonVariant.outline => (
        sr.outlineFill,
        sr.outlineHover,
        sr.onOutline,
      ),
      SrButtonVariant.ghost => (Colors.transparent, sr.ghostHover, sr.onGhost),
      SrButtonVariant.danger => (sr.dangerFill, sr.dangerHover, sr.onBrand),
    };

    final BorderSide? side = variant == SrButtonVariant.outline
        ? BorderSide(color: sr.borderStrong)
        : null;

    // `shadow-sm` on every variant except ghost, and never while disabled.
    final List<BoxShadow> shadow = variant == SrButtonVariant.ghost || !_enabled
        ? const <BoxShadow>[]
        : sr.subtleShadow;

    final Widget button = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SrRadii.control),
        boxShadow: shadow,
      ),
      child: TextButton(
        onPressed: _enabled ? onPressed : null,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.pressed) ||
                states.contains(WidgetState.hovered)) {
              return pressedFill;
            }
            return fill;
          }),
          foregroundColor: WidgetStatePropertyAll<Color>(foreground),
          overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
          elevation: const WidgetStatePropertyAll<double>(0),
          shadowColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
          surfaceTintColor: const WidgetStatePropertyAll<Color>(
            Colors.transparent,
          ),
          textStyle: WidgetStatePropertyAll<TextStyle>(size.textStyle),
          padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: size.horizontalPadding),
          ),
          minimumSize: WidgetStatePropertyAll<Size>(Size(0, size.height)),
          side: side == null ? null : WidgetStatePropertyAll<BorderSide>(side),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SrRadii.control),
            ),
          ),
          animationDuration: SrMotion.fast,
        ),
        child: Row(
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (loading)
              SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            else if (icon != null)
              Icon(icon, size: 16, color: foreground),
            if (loading || icon != null) const SizedBox(width: SrSpacing.sm),
            Flexible(
              child: Text(
                loading ? (loadingLabel ?? label) : label,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

    // § 2.6: the whole control drops to 60%, rather than each colour being
    // separately muted.
    final Widget sized = fullWidth
        ? SizedBox(width: double.infinity, child: button)
        : button;

    return _enabled ? sized : Opacity(opacity: 0.6, child: sized);
  }
}
