import 'package:flutter/material.dart';

import '../../../../core/design/design.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../campaigns/domain/entities/campaign_reward.dart';
import '../../domain/entities/campaign_reward_record.dart';
import 'earnings_copy.dart';

/// One awarded campaign reward.
///
/// ## Not tappable, and carrying no control
///
/// There is nothing to open: this application has no authorized Sales Staff
/// route that takes a reward — or a receipt submission id read off a reward — to
/// a receipt detail, and adding one would be a different feature on a different
/// contract. The receipt is shown as a **shortened reference** a seller can
/// match against their own history, which is what the reference is for.
///
/// There is no claim, redeem, withdraw or dispute action either, and none
/// disabled: no such contract exists, and an affordance would be a promise
/// nothing in this application could keep.
///
/// ## Every amount on this card is stored
///
/// [CampaignRewardRecord.coinsUncapped], [CampaignRewardRecord.rewardCoins],
/// [CampaignRewardRecord.thresholdUnits] and
/// [CampaignRewardRecord.configuredRewardCoins] are four columns the database
/// returned. When a cap bit, **both** the uncapped and the final amount are
/// shown and the difference is named — the migration keeps `coins_uncapped`
/// alongside `reward_coins` precisely so *"a screen can explain the shortfall
/// instead of a staff member discovering an unexplained number."*
///
/// ## One semantic utterance, in visual order
///
/// The card is a single semantics container labelled by
/// [EarningsCopy.rewardSemanticLabel]; its children are excluded. Without that a
/// reader would hear a dozen nodes for one reward, in an order the layout does
/// not imply.
class CampaignRewardCard extends StatelessWidget {
  const CampaignRewardCard({super.key, required this.reward});

  final CampaignRewardRecord reward;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Semantics(
      container: true,
      label: EarningsCopy.rewardSemanticLabel(reward),
      excludeSemantics: true,
      child: SrCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // -- Campaign, and how it paid -----------------------------------
            Text(
              reward.campaignName,
              style: SrTypography.cardTitle.copyWith(color: sr.foreground),
              // A 150-character campaign name is legal in the schema. Two lines
              // with an ellipsis keeps every card the same shape without the
              // name overflowing its row at any text scale.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: SrSpacing.sm),
            Wrap(
              spacing: SrSpacing.sm,
              runSpacing: SrSpacing.sm,
              children: <Widget>[
                SrBadge(
                  label: EarningsCopy.ruleLabel(reward.ruleType),
                  tone: reward.ruleType == CampaignRewardRuleType.targetBonus
                      ? SrTone.emerald
                      : SrTone.indigo,
                  icon: reward.ruleType == CampaignRewardRuleType.targetBonus
                      ? Icons.flag_outlined
                      : Icons.bolt_outlined,
                ),
                SrBadge(
                  label: EarningsCopy.rewardScopeLabel(reward.performanceScope),
                  icon: reward.performanceScope.isTeam
                      ? Icons.groups_rounded
                      : Icons.person_rounded,
                ),
              ],
            ),

            // -- What was earned ---------------------------------------------
            const SizedBox(height: SrSpacing.lg),
            _Amount(
              label: EarningsCopy.finalRewardLabel,
              value: EarningsCopy.coins(reward.rewardCoins),
            ),

            // -- The cap, when it bit -----------------------------------------
            //
            // Both stored amounts, and the reason the second is lower. Never a
            // recomputation: the database recorded the uncapped amount, the
            // ceiling it was reduced to, and the final award.
            if (reward.wasReducedByCap) ...<Widget>[
              const SizedBox(height: SrSpacing.md),
              _Fact(
                label: EarningsCopy.uncappedLabel,
                value: EarningsCopy.coins(reward.coinsUncapped),
              ),
              const SizedBox(height: SrSpacing.sm),
              const SrAlert(
                tone: SrAlertTone.warning,
                message: EarningsCopy.reducedByCap,
              ),
            ],

            // -- What qualified ------------------------------------------------
            const SizedBox(height: SrSpacing.lg),
            Wrap(
              spacing: SrSpacing.xl,
              runSpacing: SrSpacing.md,
              children: <Widget>[
                _Fact(
                  label: EarningsCopy.qualifyingProductsLabel,
                  value: EarningsCopy.qualifyingProductsValue(
                    reward.qualifyingItemCount,
                  ),
                ),
                _Fact(
                  label: EarningsCopy.qualifyingUnitsLabel,
                  value: EarningsCopy.qualifyingUnitsValue(
                    reward.qualifyingUnits,
                  ),
                ),
                // The target half of the row, present only for a TARGET_BONUS
                // reward — the schema pairs the two exactly, so a per-unit
                // reward has neither value and renders neither field.
                if (reward.thresholdUnits != null)
                  _Fact(
                    label: EarningsCopy.targetLabel,
                    value: EarningsCopy.units(reward.thresholdUnits!),
                  ),
                if (reward.configuredRewardCoins != null)
                  _Fact(
                    label: EarningsCopy.configuredBonusLabel,
                    value: EarningsCopy.coins(reward.configuredRewardCoins!),
                  ),
              ],
            ),

            // -- Where and when ------------------------------------------------
            const SizedBox(height: SrSpacing.lg),
            Wrap(
              spacing: SrSpacing.xl,
              runSpacing: SrSpacing.md,
              children: <Widget>[
                _Fact(
                  label: EarningsCopy.saleDateLabel,
                  value: formatDayDate(reward.saleAt),
                ),
                _Fact(
                  label: EarningsCopy.awardedAtLabel,
                  value: formatDayDate(reward.awardedAt),
                ),
                _Fact(
                  label: EarningsCopy.receiptLabel,
                  value: EarningsCopy.receiptReferenceValue(reward),
                ),
                // Nullable in the contract — the shop is left-joined, so one
                // that has since been removed yields null. Omitted rather than
                // dashed.
                if (reward.shopName != null)
                  _Fact(label: EarningsCopy.shopLabel, value: reward.shopName!),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The headline amount.
class _Amount extends StatelessWidget {
  const _Amount({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: SrTypography.label.copyWith(color: sr.textSecondary),
        ),
        const SizedBox(height: SrSpacing.xxs),
        // Wraps rather than clips: a large coin total at a large text scale must
        // stay readable rather than being cut off mid-number.
        Text(
          value,
          style: SrTypography.statValue.copyWith(color: sr.foreground),
          softWrap: true,
        ),
      ],
    );
  }
}

/// A labelled fact.
///
/// Width-bounded so a long shop name wraps inside the card instead of pushing
/// the row past its edge.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: SrTypography.caption.copyWith(color: sr.textMuted),
          ),
          const SizedBox(height: SrSpacing.xxs),
          Text(value, style: SrTypography.body.copyWith(color: sr.foreground)),
        ],
      ),
    );
  }
}
