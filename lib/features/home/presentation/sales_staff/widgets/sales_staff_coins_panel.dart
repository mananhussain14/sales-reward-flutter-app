import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../rewards/domain/entities/campaign_earnings_summary.dart';
import '../../../../rewards/presentation/widgets/earnings_copy.dart';
import 'sales_staff_home_copy.dart';

/// The campaign coins a seller has **earned**, as a compact strip.
///
/// ## Why this is no longer the hero
///
/// The first version gave this figure the full-width brand panel and the 30px
/// numeral. That made "what have I already earned?" the loudest question on a
/// screen whose job is "what should I do next?" — and a flat rectangle of solid
/// violet is a lot of screen to spend on one number.
///
/// It is now a **single row**: a coin disc, the total, and two supporting
/// figures as pills. It sits below the next-reward hero and is deliberately
/// quieter than it.
///
/// ## Earned, and said so
///
/// The strip carries [EarningsCopy.walletNotice] — the same sentence the
/// earnings screen shows, stating that wallet, payout and redemption do not
/// exist yet. Nothing here is netted off anything, because there is nothing to
/// net: the figure is `sum(reward_coins)` over immutable rows.
///
/// ## The count-up runs on the value, not on the build
///
/// [SrCountUp] restarts only when the total actually changes, and shows the
/// stored number whenever it is not mid-flight — so a rebuild, a rotation or a
/// tab that was hidden when the data landed all leave the true figure on
/// screen.
///
/// ## Zero is a real answer
///
/// A seller who has earned nothing sees `0 coins`, with the same wording as
/// everybody else. Never a dash, never an error, never a hidden strip.
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
  /// not answer for. Either way the strip says so rather than showing zeros,
  /// because "you earned nothing" and "we could not tell" are opposite claims.
  final bool unavailable;

  final VoidCallback onViewEarnings;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final CampaignEarningsSummary? row = summary;

    return SrCard(
      variant: SrCardVariant.interactive,
      padding: const EdgeInsets.all(SrSpacing.lg),
      onTap: onViewEarnings,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              const SrIconDisc(
                icon: Icons.savings_rounded,
                tone: SrTone.indigo,
                size: 44,
              ),
              const SizedBox(width: SrSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      SalesStaffHomeCopy.coinsSectionTitle,
                      style: SrTypography.caption.copyWith(
                        color: sr.textSecondary,
                      ),
                    ),
                    const SizedBox(height: SrSpacing.xxs),
                    if (row == null)
                      Text(
                        unavailable
                            ? SalesStaffHomeCopy.coinsUnavailable
                            : SalesStaffHomeCopy.loading,
                        style: SrTypography.label.copyWith(color: sr.textMuted),
                      )
                    else
                      // One semantics node for the whole figure: a count-up
                      // announced frame by frame would read out a dozen
                      // numbers on the way to the real one.
                      Semantics(
                        label:
                            '${SalesStaffHomeCopy.coinsSectionTitle}: '
                            '${EarningsCopy.coins(row.totalRewardCoins)}',
                        excludeSemantics: true,
                        child: SrCountUp(
                          value: row.totalRewardCoins,
                          builder: (BuildContext context, int displayed) =>
                              Text(
                                EarningsCopy.coins(displayed),
                                style: SrTypography.sectionTitle.copyWith(
                                  color: sr.foreground,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: SrSpacing.sm),
              Icon(Icons.chevron_right_rounded, size: 20, color: sr.textMuted),
            ],
          ),

          if (row != null) ...<Widget>[
            const SizedBox(height: SrSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: SrStatPill(
                    label: SalesStaffHomeCopy.thisMonthLabel,
                    value: EarningsCopy.coins(row.currentMonthRewardCoins),
                    icon: Icons.calendar_month_outlined,
                  ),
                ),
                const SizedBox(width: SrSpacing.sm),
                Expanded(
                  child: SrStatPill(
                    label: SalesStaffHomeCopy.rewardedSalesLabel,
                    value: '${row.rewardedSaleCount}',
                    icon: Icons.receipt_long_outlined,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: SrSpacing.md),
          // The qualifying notice, so nobody reads a coin total before
          // learning there is nowhere to spend it yet.
          Text(
            EarningsCopy.walletNotice,
            style: SrTypography.caption.copyWith(color: sr.textMuted),
          ),
        ],
      ),
    );
  }
}
