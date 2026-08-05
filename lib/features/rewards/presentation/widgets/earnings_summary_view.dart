import 'package:flutter/material.dart';

import '../../../../core/design/design.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/campaign_earnings_summary.dart';
import 'earnings_copy.dart';

/// The five totals from `get_my_campaign_earnings_summary()`.
///
/// ## Exact stored values, and zero is one of them
///
/// Nothing here sums, nets, rounds or projects. Each tile shows a number the
/// database returned, and a zero renders as `0` — never as a dash, an empty box
/// or an error. A seller who has earned nothing has earned nothing, and saying
/// so plainly is the honest answer.
///
/// ## Not one of these is a balance
///
/// No tile is labelled wallet balance, available balance, redeemable coins, paid
/// coins or withdrawable coins, because no such value exists: the deployed
/// schema has no ledger, no wallet and no redemption model, and nothing is
/// subtracted from anything. [EarningsCopy.walletNotice] states that above the
/// tiles rather than leaving the absence to be inferred.
class EarningsSummaryView extends StatelessWidget {
  const EarningsSummaryView({super.key, required this.summary});

  final CampaignEarningsSummary summary;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // The qualifying notice sits ABOVE the numbers, so nobody reads a coin
        // total before learning there is nowhere to spend it yet.
        const SrAlert(message: EarningsCopy.walletNotice),
        const SizedBox(height: SrSpacing.xl),

        SrResponsiveGrid(
          twoUpThreshold: 560,
          threeUpThreshold: 1024,
          children: <Widget>[
            SrStatCard(
              label: EarningsCopy.totalCoinsLabel,
              value: summary.totalRewardCoins,
              hint: EarningsCopy.totalCoinsHint,
              icon: Icons.savings_outlined,
              tone: SrTone.indigo,
            ),
            SrStatCard(
              label: EarningsCopy.currentMonthLabel,
              value: summary.currentMonthRewardCoins,
              hint: EarningsCopy.currentMonthHint(
                summary.currentMonthStartUtc,
                summary.currentMonthEndUtc,
              ),
              icon: Icons.calendar_month_outlined,
              tone: SrTone.blue,
            ),
            SrStatCard(
              label: EarningsCopy.rewardedSalesLabel,
              value: summary.rewardedSaleCount,
              hint: EarningsCopy.rewardedSalesHint,
              icon: Icons.receipt_long_outlined,
              tone: SrTone.emerald,
            ),
            SrStatCard(
              label: EarningsCopy.rewardedCampaignsLabel,
              value: summary.rewardedCampaignCount,
              hint: EarningsCopy.rewardedCampaignsHint,
              icon: Icons.campaign_outlined,
              tone: SrTone.slate,
            ),
          ],
        ),

        // -- The latest reward date ------------------------------------------
        //
        // A date rather than a count, so it does not belong in the numeric grid
        // above: `SrStatCard` takes an `int`, and formatting a timestamp into
        // one would either lie about its type or drop the "no rewards yet" case.
        const SizedBox(height: SrSpacing.lg),
        SrCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ExcludeSemantics(
                child: Icon(
                  Icons.event_available_outlined,
                  size: 18,
                  color: sr.textMuted,
                ),
              ),
              const SizedBox(width: SrSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      EarningsCopy.latestRewardLabel,
                      style: SrTypography.label.copyWith(
                        color: sr.textSecondary,
                      ),
                    ),
                    const SizedBox(height: SrSpacing.xxs),
                    Text(
                      EarningsCopy.latestRewardValue(summary.latestRewardAt),
                      style: SrTypography.bodyLarge.copyWith(
                        color: sr.foreground,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
