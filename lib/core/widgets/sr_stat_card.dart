import 'package:flutter/material.dart';

import '../design/design.dart';
import 'sr_card.dart';

/// A metric card, translated from `StatCard` in the web application's
/// `components/admin/stat-card.tsx`.
///
/// ## `null` is not zero
///
/// The web component encodes a distinction worth preserving exactly: a [value]
/// of `null` means "the figure could not be read", and renders as **Unavailable**
/// — not `0`, and not an em dash. `0` is a valid count and renders as `0`.
///
/// The reason is never shown, because the only thing that could produce it is a
/// backend error whose detail must not reach the client.
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

  /// Short supporting context under the value.
  final String hint;

  final IconData? icon;
  final SrTone tone;
  final VoidCallback? onTap;

  /// Groups digits with commas in a fixed locale, as the web does, so the
  /// output never varies by device settings.
  static String _format(int value) {
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
                  style: SrTypography.body.copyWith(
                    fontWeight: FontWeight.w500,
                    color: SrColors.textMuted,
                  ),
                ),
              ),
              if (icon != null) ...<Widget>[
                const SizedBox(width: SrSpacing.md),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: tone.background,
                    borderRadius: BorderRadius.circular(SrRadii.lg),
                  ),
                  child: Icon(icon, size: 20, color: tone.foreground),
                ),
              ],
            ],
          ),
          const SizedBox(height: SrSpacing.md),
          if (value == null)
            Text(
              'Unavailable',
              style: SrTypography.sectionTitle.copyWith(
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
                color: SrColors.slate400,
              ),
            )
          else
            Text(
              _format(value!),
              style: SrTypography.pageTitle.copyWith(
                fontSize: 30,
                height: 36 / 30,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          const SizedBox(height: SrSpacing.xs),
          Text(
            hint,
            style: SrTypography.caption.copyWith(color: SrColors.slate400),
          ),
        ],
      ),
    );
  }
}
