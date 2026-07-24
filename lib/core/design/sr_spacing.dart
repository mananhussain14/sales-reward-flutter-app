/// The spacing rhythm, translated from Tailwind's 4px scale as the web
/// components use it.
///
/// The web app never invents a spacing value: every gap, pad and margin is a
/// step on Tailwind's `0.25rem` scale. Naming the steps here (rather than
/// writing `16` at call sites) is what keeps the mobile rhythm identical to the
/// web's, and makes a deviation visible in review.
abstract final class SrSpacing {
  /// `0.5` → 2px
  static const double xxs = 2;

  /// `1` → 4px
  static const double xs = 4;

  /// `1.5` → 6px
  static const double xsPlus = 6;

  /// `2` → 8px — the base gap inside a control (icon ↔ label).
  static const double sm = 8;

  /// `2.5` → 10px — horizontal padding of a status badge.
  static const double smPlus = 10;

  /// `3` → 12px
  static const double md = 12;

  /// `3.5` → 14px — horizontal padding of a form control.
  static const double mdPlus = 14;

  /// `4` → 16px — the default gap between siblings.
  static const double lg = 16;

  /// `5` → 20px — card padding on narrow screens (`p-5`).
  static const double xl = 20;

  /// `6` → 24px — card padding on wider screens (`sm:p-6`), page gutters.
  static const double xxl = 24;

  /// `8` → 32px — separation between major page sections.
  static const double xxxl = 32;

  /// `12` → 48px — vertical padding of an empty state (`py-12`).
  static const double huge = 48;

  /// The maximum content width for a page body. Phones never reach it; tablets
  /// and Flutter web do, and without it a card would stretch to 1400px and stop
  /// resembling the web product at all.
  static const double contentMaxWidth = 720;

  /// Below this width the shells use bottom navigation; at or above it they use
  /// a navigation rail. Matches Material's compact/medium window breakpoint.
  static const double railBreakpoint = 640;

  /// At or above this width a navigation drawer can stay permanently open
  /// beside the content instead of being summoned modally.
  static const double expandedBreakpoint = 1024;
}

/// The corner radii, translated from the Tailwind `rounded-*` steps the web
/// components use.
abstract final class SrRadii {
  /// `rounded-md` → 6px — skeleton blocks.
  static const double sm = 6;

  /// `rounded-lg` → 8px — back links, small hit targets.
  static const double md = 8;

  /// `rounded-xl` → 12px — buttons and every form control.
  static const double lg = 12;

  /// `rounded-2xl` → 16px — cards, sheets, tinted icon discs.
  static const double xl = 16;

  /// The brand mark tile's radius at its 40px reference size (`rx="11"`).
  static const double brandTile = 11;

  /// `rounded-full` — status badges and avatars.
  static const double full = 9999;
}
