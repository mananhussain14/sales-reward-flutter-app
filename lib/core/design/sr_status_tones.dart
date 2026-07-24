import 'package:flutter/material.dart';

import 'sr_colors.dart';

/// The six status tones, translated from `TONE_CLASSES` in the web
/// application's `components/ui/badge.tsx`.
///
/// Each tone is a tinted background, a saturated foreground, and a 1px inset
/// ring at 20% of the 600-step — the exact recipe the web uses.
enum SrTone {
  emerald,
  amber,
  indigo,
  blue,
  slate,
  red;

  /// `bg-*-50` (slate uses `bg-slate-100`).
  Color get background => switch (this) {
    SrTone.emerald => SrColors.emerald50,
    SrTone.amber => SrColors.amber50,
    SrTone.indigo => SrColors.indigo50,
    SrTone.blue => SrColors.blue50,
    SrTone.slate => SrColors.slate100,
    SrTone.red => SrColors.red50,
  };

  /// `text-*-700` (slate uses `text-slate-600`).
  Color get foreground => switch (this) {
    SrTone.emerald => SrColors.emerald700,
    SrTone.amber => SrColors.amber700,
    SrTone.indigo => SrColors.indigo700,
    SrTone.blue => SrColors.blue700,
    SrTone.slate => SrColors.textSecondary,
    SrTone.red => SrColors.red700,
  };

  /// `ring-*-600/20` (slate uses `ring-slate-500/20`).
  Color get ring => switch (this) {
    SrTone.emerald => SrColors.emerald600.withValues(alpha: 0.2),
    SrTone.amber => SrColors.amber600.withValues(alpha: 0.2),
    SrTone.indigo => SrColors.indigo600.withValues(alpha: 0.2),
    SrTone.blue => SrColors.blue700.withValues(alpha: 0.2),
    SrTone.slate => SrColors.slate500.withValues(alpha: 0.2),
    SrTone.red => SrColors.red600.withValues(alpha: 0.2),
  };

  /// The stronger 100/700 pairing used by the icon disc inside a status card
  /// (`DISC_TONES` in `components/ui/status-card.tsx`).
  Color get discBackground => switch (this) {
    SrTone.emerald => SrColors.emerald100,
    SrTone.amber => SrColors.amber100,
    SrTone.indigo => SrColors.indigo100,
    SrTone.blue => SrColors.blue50,
    SrTone.slate => SrColors.slate100,
    SrTone.red => SrColors.red100,
  };
}
