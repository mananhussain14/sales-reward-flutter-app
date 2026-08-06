import 'package:flutter/material.dart';

import '../../../../core/design/design.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/campaign_earnings_summary.dart';
import 'earnings_copy.dart';

/// The five totals from `get_my_campaign_earnings_summary()`.
///
/// ## One hero, four supporting facts
///
/// The total is the reason a seller opens this screen, so it gets the brand
/// panel and the 30px figure; everything else is a tile. Giving all five equal
/// weight — which is what a uniform grid does — is what made this screen read as
/// an administrative report rather than as a record of what somebody earned.
///
/// ## Exact stored values, and zero is one of them
///
/// Nothing here sums, nets, rounds or projects. Each figure is a number the
/// database returned, and a zero renders as `0` — never as a dash, an empty box
/// or an error. A seller who has earned nothing has earned nothing, and saying
/// so plainly is the honest answer.
///
/// The count-up is a **presentation** of that number and never a different one:
/// it ends on the stored value, it runs once per change rather than once per
/// build, and under reduced motion the first frame is the last.
///
/// ## Not one of these is a balance
///
/// No tile is labelled wallet balance, available balance, redeemable coins,
/// paid coins or withdrawable coins, because no such value exists: the deployed
/// schema has no ledger, no wallet and no redemption model, and nothing is
/// subtracted from anything. [EarningsCopy.walletNotice] states that on the
/// panel itself rather than leaving the absence to be inferred.
class EarningsSummaryView extends StatelessWidget {
  const EarningsSummaryView({super.key, required this.summary});

  final CampaignEarningsSummary summary;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SrEnter(
          child: SrHeroPanel(
            icon: Icons.savings_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  EarningsCopy.totalCoinsLabel,
                  style: SrTypography.label.copyWith(
                    color: sr.onBrand.withValues(alpha: 0.82),
                  ),
                ),
                const SizedBox(height: SrSpacing.sm),
                // One semantics node for the whole figure: a count-up announced
                // frame by frame would read out a dozen numbers on the way to
                // the real one.
                Semantics(
                  label:
                      '${EarningsCopy.totalCoinsLabel}: '
                      '${EarningsCopy.coins(summary.totalRewardCoins)}',
                  excludeSemantics: true,
                  child: SrCountUp(
                    value: summary.totalRewardCoins,
                    builder: (BuildContext context, int displayed) => Text(
                      EarningsCopy.coins(displayed),
                      style: SrTypography.statValue.copyWith(color: sr.onBrand),
                      softWrap: true,
                    ),
                  ),
                ),
                const SizedBox(height: SrSpacing.xs),
                Text(
                  EarningsCopy.totalCoinsHint,
                  style: SrTypography.caption.copyWith(
                    color: sr.onBrand.withValues(alpha: 0.80),
                  ),
                ),
                const SizedBox(height: SrSpacing.lg),
                // The qualifying notice sits ON the figure's own panel, so
                // nobody reads a coin total before learning there is nowhere to
                // spend it yet.
                Text(
                  EarningsCopy.walletNotice,
                  style: SrTypography.caption.copyWith(
                    color: sr.onBrand.withValues(alpha: 0.80),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: SrSpacing.lg),

        SrResponsiveGrid(
          twoUpThreshold: 560,
          threeUpThreshold: 1024,
          children: <Widget>[
            SrEnter(
              index: 1,
              child: _MetricTile(
                label: EarningsCopy.currentMonthLabel,
                value: summary.currentMonthRewardCoins,
                hint: EarningsCopy.currentMonthHint(
                  summary.currentMonthStartUtc,
                  summary.currentMonthEndUtc,
                ),
                icon: Icons.calendar_month_outlined,
                tone: SrTone.blue,
              ),
            ),
            SrEnter(
              index: 2,
              child: _MetricTile(
                label: EarningsCopy.rewardedSalesLabel,
                value: summary.rewardedSaleCount,
                hint: EarningsCopy.rewardedSalesHint,
                icon: Icons.receipt_long_outlined,
                tone: SrTone.emerald,
              ),
            ),
            SrEnter(
              index: 3,
              child: _MetricTile(
                label: EarningsCopy.rewardedCampaignsLabel,
                value: summary.rewardedCampaignCount,
                hint: EarningsCopy.rewardedCampaignsHint,
                icon: Icons.campaign_outlined,
                tone: SrTone.indigo,
              ),
            ),
          ],
        ),

        // -- The latest reward date ------------------------------------------
        //
        // A date rather than a count, so it does not belong in the numeric grid
        // above: a tile that counts up to a timestamp would either lie about
        // its type or drop the "no rewards yet" case.
        const SizedBox(height: SrSpacing.lg),
        SrEnter(
          index: 4,
          child: SrCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                const SrIconDisc(
                  icon: Icons.event_available_outlined,
                  tone: SrTone.slate,
                  size: 40,
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
        ),
      ],
    );
  }
}

/// One supporting figure.
///
/// The geometry of [SrStatCard] — 14/500 label, 40px tinted disc, 30px value
/// with tabular figures, 12px hint — with the value animated. It is a local
/// widget rather than a change to the shared card because only this screen
/// counts up: a dashboard tile that animated every time a Vendor's list
/// refreshed would be movement without meaning.
class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.tone,
  });

  final String label;

  /// The authoritative count. Zero is a real answer and renders as `0`.
  final int value;

  final String hint;
  final IconData icon;
  final SrTone tone;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return SrCard(
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
              const SizedBox(width: SrSpacing.md),
              SrIconDisc(icon: icon, tone: tone, size: 40),
            ],
          ),
          const SizedBox(height: SrSpacing.md),
          Semantics(
            label: '$label: ${SrStatCard.format(value)}',
            excludeSemantics: true,
            child: SrCountUp(
              value: value,
              builder: (BuildContext context, int displayed) => Text(
                SrStatCard.format(displayed),
                style: SrTypography.statValue.copyWith(color: sr.foreground),
              ),
            ),
          ),
          const SizedBox(height: SrSpacing.xs),
          Text(hint, style: SrTypography.caption.copyWith(color: sr.textMuted)),
        ],
      ),
    );
  }
}
