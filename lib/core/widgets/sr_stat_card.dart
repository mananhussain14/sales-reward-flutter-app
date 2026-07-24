import 'package:flutter/material.dart';

import '../design/design.dart';
import 'sr_card.dart';

/// A metric card (§ 3.5).
///
/// Label at 14/500 top-left, a 40px tinted disc top-right, then the value at
/// 30px semibold with tabular figures, then a 12px hint.
///
/// ## `null` is not zero
///
/// A [value] of `null` means "the figure could not be read" and renders
/// **"Unavailable"** at 18px/500 in the muted tone — not `0`, and not an em
/// dash. `0` is a real count and renders as `0`.
///
/// The reason is never shown. The only thing that can produce it is a backend
/// error whose detail must not reach a client.
class SrStatCard extends StatelessWidget {
  const SrStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.hint,
    this.icon,
    this.tone = SrTone.indigo,
    this.onTap,
  });

  final String label;

  /// The real count, or null when it could not be read.
  final int? value;

  final String hint;
  final IconData? icon;
  final SrTone tone;
  final VoidCallback? onTap;

  /// Groups digits in a fixed locale, as the web's `toLocaleString("en-US")`
  /// does, so the output never varies by device settings.
  static String format(int value) {
    final String digits = value.abs().toString();
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[i]);
    }
    return value < 0 ? '-$buffer' : buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return SrCard(
      variant: onTap == null
          ? SrCardVariant.standard
          : SrCardVariant.interactive,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: SrTypography.label.copyWith(color: sr.textSecondary),
                ),
              ),
              if (icon != null) ...<Widget>[
                const SizedBox(width: SrSpacing.md),
                SrIconDisc(icon: icon!, tone: tone, size: 40),
              ],
            ],
          ),
          const SizedBox(height: SrSpacing.md),
          if (value == null)
            Text(
              'Unavailable',
              style: SrTypography.statUnavailable.copyWith(color: sr.textMuted),
            )
          else
            Text(
              format(value!),
              style: SrTypography.statValue.copyWith(color: sr.foreground),
            ),
          const SizedBox(height: SrSpacing.xs),
          Text(hint, style: SrTypography.caption.copyWith(color: sr.textMuted)),
        ],
      ),
    );
  }
}
