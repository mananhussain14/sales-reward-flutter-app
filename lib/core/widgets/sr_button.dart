import 'package:flutter/material.dart';

import '../design/design.dart';

/// The button variants, mirroring `VARIANTS` in the web application's
/// `components/ui/button.tsx`.
enum SrButtonVariant {
  /// `bg-indigo-600 text-white` — the primary call to action.
  primary,

  /// `bg-slate-900 text-white` — a strong but non-brand action.
  secondary,

  /// `border-slate-300 bg-white text-slate-700` — the default secondary.
  outline,

  /// `text-slate-600 hover:bg-slate-100` — a low-emphasis action.
  ghost,

  /// `bg-red-600 text-white` — a destructive action.
  danger,
}

/// The button sizes, mirroring `SIZES` in `button.tsx`.
enum SrButtonSize {
  /// `h-9 px-3 text-sm`
  sm(
    height: 36,
    horizontalPadding: SrSpacing.md,
    textStyle: SrTypography.button,
  ),

  /// `h-11 px-4 text-sm` — the default.
  md(
    height: 44,
    horizontalPadding: SrSpacing.lg,
    textStyle: SrTypography.button,
  ),

  /// `h-12 px-5 text-base`
  lg(
    height: 48,
    horizontalPadding: SrSpacing.xl,
    textStyle: SrTypography.buttonLarge,
  );

  const SrButtonSize({
    required this.height,
    required this.horizontalPadding,
    required this.textStyle,
  });

  final double height;
  final double horizontalPadding;
  final TextStyle textStyle;
}

/// The shared button, translated from `components/ui/button.tsx`.
///
/// Carries the same geometry (12px radius, semibold label, 8px icon gap), the
/// same variant palette, and the same built-in busy state: while [loading] the
/// button shows a spinner, optionally swaps its label, and is disabled — so a
/// double submit is prevented by the control itself.
///
/// That last property is not cosmetic. The backend contract records that
/// `onboard_vendor_retailer()` has **no idempotency guard**, so a double submit
/// creates two Retailers. Disabling on submit is the client's half of that.
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

  /// Shows a spinner and disables the button.
  final bool loading;

  /// Optional label shown while [loading]. Falls back to [label].
  final String? loadingLabel;

  final bool fullWidth;

  bool get _enabled => onPressed != null && !loading;

  Color get _background => switch (variant) {
    SrButtonVariant.primary => SrColors.brand,
    SrButtonVariant.secondary => SrColors.slate900,
    SrButtonVariant.outline => SrColors.surface,
    SrButtonVariant.ghost => Colors.transparent,
    SrButtonVariant.danger => SrColors.red600,
  };

  Color get _pressedBackground => switch (variant) {
    SrButtonVariant.primary => SrColors.brandHover,
    SrButtonVariant.secondary => SrColors.slate800,
    SrButtonVariant.outline => SrColors.slate50,
    SrButtonVariant.ghost => SrColors.slate100,
    SrButtonVariant.danger => SrColors.red700,
  };

  Color get _foreground => switch (variant) {
    SrButtonVariant.primary ||
    SrButtonVariant.secondary ||
    SrButtonVariant.danger => SrColors.white,
    SrButtonVariant.outline => SrColors.slate700,
    SrButtonVariant.ghost => SrColors.textSecondary,
  };

  BorderSide? get _side => switch (variant) {
    SrButtonVariant.outline => const BorderSide(color: SrColors.borderStrong),
    _ => null,
  };

  /// `shadow-sm` on every filled and outlined variant; the ghost variant has
  /// none, exactly as on the web.
  List<BoxShadow> get _shadow => switch (variant) {
    SrButtonVariant.ghost => const <BoxShadow>[],
    _ => SrShadows.subtle,
  };

  @override
  Widget build(BuildContext context) {
    final ButtonStyle style = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.disabled)) {
          // `disabled:opacity-60`
          return Color.alphaBlend(
            _background.withValues(alpha: 0.6),
            SrColors.appBackground,
          );
        }
        if (states.contains(WidgetState.pressed) ||
            states.contains(WidgetState.hovered)) {
          return _pressedBackground;
        }
        return _background;
      }),
      foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.disabled)) {
          return _foreground.withValues(alpha: 0.6);
        }
        return _foreground;
      }),
      overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      elevation: const WidgetStatePropertyAll<double>(0),
      shadowColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      textStyle: WidgetStatePropertyAll<TextStyle>(size.textStyle),
      padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: size.horizontalPadding),
      ),
      minimumSize: WidgetStatePropertyAll<Size>(Size(0, size.height)),
      side: _side == null ? null : WidgetStatePropertyAll<BorderSide>(_side!),
      shape: WidgetStatePropertyAll<OutlinedBorder>(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(SrRadii.lg)),
      ),
      animationDuration: SrMotion.fast,
    );

    final Widget button = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SrRadii.lg),
        boxShadow: _enabled ? _shadow : const <BoxShadow>[],
      ),
      child: TextButton(
        onPressed: _enabled ? onPressed : null,
        style: style,
        child: Row(
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (loading)
              SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _foreground,
                ),
              )
            else if (icon != null)
              Icon(icon, size: 16, color: _foreground),
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

    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}
