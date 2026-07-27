import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';

/// One shop count from the overview row.
///
/// Deliberately **not** `SrStatCard`. That widget models a nullable figure and
/// renders "Unavailable" for null, which is right for the web's per-card
/// degradation and wrong here. This contract has no per-card failure: both
/// counts are non-null `bigint`, both arrive in the same row as everything else,
/// and a refusal or a malformed body takes the whole screen rather than one
/// card. A card that could render "Unavailable" would be a card someone could
/// later make render `0` for the same reason — and `0` is a real answer meaning
/// "no shops yet".
///
/// So [value] is non-nullable, and there is no code path here that produces a
/// number the backend did not send.
///
/// ## Accessibility
///
/// The whole card is one semantics node reading "label: value. hint." — one
/// sentence rather than three fragments a reader would have to reassemble. The
/// visual tree is excluded beneath it so the figure is not announced twice, once
/// formatted and once raw.
class RetailerShopCountCard extends StatelessWidget {
  const RetailerShopCountCard({
    super.key,
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    this.tone = SrTone.indigo,
  });

  final String label;

  /// A real count. Never null, and never a placeholder.
  final int value;

  final String hint;
  final IconData icon;
  final SrTone tone;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final SrToneColors colors = sr.tone(tone);

    return Semantics(
      label: '$label: $value. $hint.',
      excludeSemantics: true,
      child: SrCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colors.discFill,
                    borderRadius: BorderRadius.circular(SrRadii.control),
                  ),
                  child: Icon(icon, size: 18, color: colors.foreground),
                ),
                const SizedBox(width: SrSpacing.md),
                Expanded(
                  child: Text(
                    label,
                    style: SrTypography.label.copyWith(color: sr.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SrSpacing.lg),
            Text(
              '$value',
              style: SrTypography.statValue.copyWith(color: sr.foreground),
            ),
            const SizedBox(height: SrSpacing.xs),
            Text(
              hint,
              style: SrTypography.caption.copyWith(color: sr.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
