import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../rewards/domain/entities/campaign_earnings_summary.dart';
import '../../../../rewards/presentation/widgets/earnings_copy.dart';
import 'sales_staff_home_copy.dart';

/// The campaign coins a seller has **earned**, as the home screen's one hero.
///
/// ## Earned, and said so twice
///
/// The panel is titled "Campaign coins earned" and carries
/// [EarningsCopy.walletNotice] underneath it — the same sentence the earnings
/// screen shows, stating that wallet, payout and redemption do not exist yet.
/// Nothing here is netted off anything, because there is nothing to net: the
/// figure is `sum(reward_coins)` over immutable rows the database already has.
///
/// ## The count-up runs on the value, not on the build
///
/// [SrCountUp] restarts only when the total actually changes, so a Bloc that
/// emits an equal state, a rotation, a theme change or a parent rebuild leave
/// the number where it is. It counts **to** the stored total and stops there —
/// the last frame is the number the backend returned, and under reduced motion
/// it is the only frame.
///
/// ## Zero is a real answer
///
/// A seller who has earned nothing sees `0`, animated from nothing to nothing,
/// with the same wording as everybody else. It is never a dash, an error, or a
/// hidden panel.
class SalesStaffCoinsPanel extends StatelessWidget {
  const SalesStaffCoinsPanel({
    super.key,
    required this.summary,
    required this.unavailable,
    required this.onViewEarnings,
  });

  /// The authoritative summary, or null when it has not arrived.
  final CampaignEarningsSummary? summary;

  /// The totals could not be read — a failure, or a caller the contract does
  /// not answer for. Either way the panel says so rather than showing zeros,
  /// because "you earned nothing" and "we could not tell" are opposite claims.
  final bool unavailable;

  final VoidCallback onViewEarnings;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final CampaignEarningsSummary? row = summary;

    return SrHeroPanel(
      icon: Icons.savings_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            SalesStaffHomeCopy.coinsSectionTitle,
            style: SrTypography.label.copyWith(
              color: sr.onBrand.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: SrSpacing.sm),

          if (row == null)
            Text(
              unavailable
                  ? SalesStaffHomeCopy.coinsUnavailable
                  : SalesStaffHomeCopy.loading,
              style: SrTypography.bodyLarge.copyWith(color: sr.onBrand),
            )
          else ...<Widget>[
            // One semantics node for the whole figure: a count-up announced
            // frame by frame would read out a dozen numbers on the way to the
            // real one.
            Semantics(
              label:
                  '${SalesStaffHomeCopy.coinsSectionTitle}: '
                  '${EarningsCopy.coins(row.totalRewardCoins)}',
              excludeSemantics: true,
              child: SrCountUp(
                value: row.totalRewardCoins,
                builder: (BuildContext context, int displayed) => Text(
                  EarningsCopy.coins(displayed),
                  style: SrTypography.statValue.copyWith(color: sr.onBrand),
                  softWrap: true,
                ),
              ),
            ),
            const SizedBox(height: SrSpacing.md),
            Wrap(
              spacing: SrSpacing.xxl,
              runSpacing: SrSpacing.md,
              children: <Widget>[
                SrHeroFact(
                  label: SalesStaffHomeCopy.thisMonthLabel,
                  value: EarningsCopy.coins(row.currentMonthRewardCoins),
                ),
                SrHeroFact(
                  label: SalesStaffHomeCopy.rewardedSalesLabel,
                  value: '${row.rewardedSaleCount}',
                ),
                SrHeroFact(
                  label: SalesStaffHomeCopy.rewardedCampaignsLabel,
                  value: '${row.rewardedCampaignCount}',
                ),
              ],
            ),
          ],

          const SizedBox(height: SrSpacing.lg),
          // The qualifying notice, on the panel itself rather than a screen
          // away — so nobody reads a coin total before learning there is
          // nowhere to spend it yet.
          Text(
            EarningsCopy.walletNotice,
            style: SrTypography.caption.copyWith(
              color: sr.onBrand.withValues(alpha: 0.80),
            ),
          ),
          const SizedBox(height: SrSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: _OnBrandButton(
              label: SalesStaffHomeCopy.coinsAction,
              icon: Icons.arrow_forward_rounded,
              onPressed: onViewEarnings,
            ),
          ),
        ],
      ),
    );
  }
}

/// A button sized and coloured for the brand-filled panel.
///
/// [SrButton]'s five variants are all tuned for the ordinary surface ramp; an
/// outline button on a brand fill would draw a slate hairline on indigo. This
/// keeps the product's geometry — 44 high, 12 radius, semibold label, 8px icon
/// gap — and swaps only the two colours the panel requires.
class _OnBrandButton extends StatelessWidget {
  const _OnBrandButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: sr.onBrand.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(SrRadii.control),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(SrRadii.control),
          child: Container(
            height: SrButtonSize.md.height,
            padding: const EdgeInsets.symmetric(horizontal: SrSpacing.lg),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // Flexible rather than fixed: at a large text scale on a narrow
                // phone the label is wider than the panel, and a Row of
                // intrinsic children would overflow rather than ellipsise.
                Flexible(
                  child: Text(
                    label,
                    style: SrTypography.button.copyWith(color: sr.onBrand),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: SrSpacing.sm),
                Icon(icon, size: 16, color: sr.onBrand),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
