/// The SalesReward design tokens.
///
/// One import for the whole token layer. Every value traces to a numbered
/// section of `docs/mobile-ui-design-handoff.md` in the `salesreward-admin`
/// repository; the individual files record which.
///
/// Layering:
///
/// * [SrPalette] — raw Tailwind v4 scale steps. Rarely used directly.
/// * [SrColorScheme] — the semantic layer, resolved per theme and read from a
///   widget through `context.sr`.
/// * [SrTypography], [SrSpacing], [SrRadii], [SrMotion] — theme-independent
///   geometry.
library;

export 'sr_color_scheme.dart';
export 'sr_motion.dart';
export 'sr_palette.dart';
export 'sr_spacing.dart';
export 'sr_typography.dart';
