/// The spacing rhythm, transcribed from § 2.9 of
/// `docs/mobile-ui-design-handoff.md`.
///
/// Tailwind v4's base unit is `0.25rem`, so utility `n` renders `4n` px. The
/// web never invents a spacing value; naming the steps here — rather than
/// writing `16` at call sites — is what keeps the mobile rhythm identical and
/// makes a deviation visible in review.
abstract final class SrSpacing {
  /// `0.5` → 2
  static const double xxs = 2;

  /// `1` → 4
  static const double xs = 4;

  /// `1.5` → 6 — empty-state title → description.
  static const double xsPlus = 6;

  /// `2` → 8 — label → control, control → message, icon → label in a button.
  static const double sm = 8;

  /// `2.5` → 10 — badge horizontal padding, brand lockup gap.
  static const double smPlus = 10;

  /// `3` → 12 — nav item horizontal padding, nav icon → label, card list gap.
  static const double md = 12;

  /// `3.5` → 14 — form control horizontal padding.
  static const double mdPlus = 14;

  /// `4` → 16 — grid gutter, card body padding, main content padding on a
  /// phone.
  static const double lg = 16;

  /// `5` → 20 — card padding, and the gap between fields in a form.
  static const double xl = 20;

  /// `6` → 24 — card padding at `sm`+, page section stack, empty-state
  /// horizontal padding.
  static const double xxl = 24;

  /// `8` → 32 — the wider page section stack, and auth card padding at `sm`+.
  static const double xxxl = 32;

  /// `12` → 48 — empty-state vertical padding.
  static const double huge = 48;

  /// `max-w-6xl` = 1152 — dashboards and lists.
  static const double contentMaxWidth = 1152;

  /// `max-w-2xl` = 672 — form pages and page-header descriptions.
  static const double formMaxWidth = 672;

  /// `max-w-md` = 448 — auth, invitation and access-denied surfaces.
  static const double compactMaxWidth = 448;

  /// `max-w-sm` = 384 — the login form, and an empty-state description.
  static const double narrowMaxWidth = 384;

  /// `w-64` = 256 — the sidebar, and therefore the drawer.
  static const double navWidth = 256;

  /// `h-16` = 64 — the app bar, and the sidebar header.
  static const double appBarHeight = 64;

  /// Tailwind `sm`. Below it the phone layout applies.
  static const double breakpointSm = 640;

  /// Tailwind `md`. The web swaps its card lists for tables here.
  static const double breakpointMd = 768;

  /// Tailwind `lg`. The web's drawer becomes a permanent sidebar here.
  static const double breakpointLg = 1024;
}

/// The corner radii, transcribed from § 2.8.
///
/// > There are **three** radii to internalise: **12 for controls, 16 for
/// > surfaces, full for pills.** Nothing in the product uses 4 or 24.
abstract final class SrRadii {
  /// `rounded-md` → 6 — skeleton blocks only.
  static const double skeleton = 6;

  /// `rounded-lg` → 8 — small inline controls and chips.
  static const double sm = 8;

  /// `rounded-xl` → 12 — **controls**: buttons, inputs, alerts, nav items,
  /// icon buttons, and the 10 × 10 icon disc.
  static const double control = 12;

  /// `rounded-2xl` → 16 — **surfaces**: cards, sheets, dialogs, empty states,
  /// and the 11–14 icon discs.
  static const double surface = 16;

  /// The brand tile's radius on its 40px reference grid.
  static const double brandTile = 11;

  /// `rounded-full` — badges, avatars, timeline nodes, the active nav rail.
  static const double full = 9999;
}
