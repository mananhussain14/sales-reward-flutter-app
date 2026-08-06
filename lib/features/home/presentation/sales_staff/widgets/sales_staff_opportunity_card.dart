import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/utils/date_format.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../campaigns/domain/entities/campaign_lifecycle_state.dart';
import '../../../../campaigns/domain/entities/campaign_offer.dart';
import '../../../../campaigns/domain/entities/campaign_product_eligibility.dart';
import '../../../../campaigns/domain/entities/campaign_reward.dart';
import '../../../../campaigns/presentation/shared/campaign_card.dart';
import '../../../../campaigns/presentation/shared/campaign_copy.dart';
import '../../../../campaigns/presentation/shared/campaign_presentation.dart';
import '../../../../rewards/domain/entities/campaign_target_progress.dart';
import '../../../../rewards/presentation/widgets/earnings_copy.dart';
import 'sales_staff_opportunity.dart';

/// One campaign in the home screen's horizontal carousel.
///
/// ## Eight campaigns, eight faces
///
/// The complaint the redesign answers is that every campaign looked the same.
/// It no longer does, and the difference is driven entirely by columns the
/// contract already returns:
///
/// | What the contract says | What the card becomes |
/// | --- | --- |
/// | `PER_UNIT_COINS` | a coin disc and the **rate** as the headline |
/// | `TARGET_BONUS`, `INDIVIDUAL_STAFF` | a mini gauge and the remaining units |
/// | `TARGET_BONUS`, `RETAILER_TEAM` | a team disc, team wording, and who took the bonus |
/// | `SCHEDULED` | a calendar disc and the start date instead of progress |
/// | `max_reward_coins` non-null | a cap pill |
/// | `EXCLUSIVE` | an exclusivity pill |
/// | `SNAPSHOT` | a locked-selection pill |
/// | `LIVE_TEMPORAL` | a checked-at-sale-time pill |
///
/// The last four are **additive** — a campaign can be a capped, exclusive,
/// snapshot per-unit campaign and shows all of it — so the combinations the
/// deployed schema permits are all representable without a special case.
///
/// ## Fixed width, on purpose
///
/// A carousel of variable-width cards has no rhythm and cannot be paged. The
/// card is [width] wide at every text scale; its content wraps inside that.
///
/// ## One announcement
///
/// The whole card is a single button whose label is the shared campaign
/// utterance, plus the progress sentence when there is a gauge. Its children
/// are excluded, so a reader hears one card rather than nine nodes.
class SalesStaffOpportunityCard extends StatelessWidget {
  const SalesStaffOpportunityCard({
    super.key,
    required this.opportunity,
    required this.onOpen,
  });

  final SalesStaffOpportunity opportunity;
  final VoidCallback onOpen;

  /// Wide enough for a rate headline and two pills, narrow enough that the
  /// next card peeks in on a 390px phone — which is what says "there is more".
  static const double width = 268;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final CampaignOffer offer = opportunity.campaign.offer;
    final CampaignTargetProgress? row = opportunity.progress;
    final bool scheduled =
        offer.lifecycleState == CampaignLifecycleState.scheduled;

    final (SrTone tone, IconData icon) = _face(offer, row, scheduled);

    return Semantics(
      button: true,
      label: _semanticLabel(),
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        child: SrPressScale(
          child: SrCard(
            variant: SrCardVariant.interactive,
            padding: const EdgeInsets.all(SrSpacing.lg),
            onTap: onOpen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SrIconDisc(icon: icon, tone: tone, size: 40),
                    const SizedBox(width: SrSpacing.md),
                    Expanded(
                      child: Text(
                        offer.name,
                        style: SrTypography.label.copyWith(
                          color: sr.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: SrSpacing.lg),

                // -- The face of this campaign type ----------------------
                if (scheduled)
                  _ScheduledFace(offer: offer)
                else if (row != null)
                  _TargetFace(progress: row, tone: tone)
                else
                  _PerUnitFace(
                    offer: offer,
                    audience: opportunity.campaign.audience,
                  ),

                const SizedBox(height: SrSpacing.md),
                _Qualifiers(offer: offer),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The disc's tone and glyph — the card's whole identity in one pair.
  static (SrTone, IconData) _face(
    CampaignOffer offer,
    CampaignTargetProgress? progress,
    bool scheduled,
  ) {
    if (scheduled) {
      return (SrTone.blue, Icons.event_available_rounded);
    }
    if (progress != null) {
      if (progress.targetReached) {
        return (SrTone.emerald, Icons.emoji_events_rounded);
      }
      return progress.performanceScope.isTeam
          ? (SrTone.amber, Icons.groups_rounded)
          : (SrTone.indigo, Icons.my_location_rounded);
    }
    return CampaignCard.accentFor(offer.reward);
  }

  String _semanticLabel() {
    final StringBuffer buffer = StringBuffer(
      CampaignCopy.cardSemanticLabel(opportunity.campaign),
    );
    final CampaignTargetProgress? row = opportunity.progress;
    if (row != null) {
      buffer
        ..write(' ')
        ..write(EarningsCopy.progressSemanticLabel(row));
    }
    return buffer.toString();
  }
}

/// A per-unit campaign leads with its **rate**, because that is the whole
/// offer: there is no threshold to draw and no progress to report.
class _PerUnitFace extends StatelessWidget {
  const _PerUnitFace({required this.offer, required this.audience});

  final CampaignOffer offer;
  final CampaignAudience audience;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final CampaignReward reward = offer.reward;

    if (reward is! CampaignPerUnitReward) {
      // A target campaign with no progress row — the reading session has not
      // run that contract. The offer is still the honest thing to show.
      return Text(
        CampaignCopy.rewardSentence(offer, audience),
        style: SrTypography.body.copyWith(color: sr.textBody),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Flexible(
              child: Text(
                EarningsCopy.coins(reward.coinsPerUnit),
                style: SrTypography.statValue.copyWith(color: sr.foreground),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        Text(
          'per eligible unit',
          style: SrTypography.caption.copyWith(color: sr.textSecondary),
        ),
      ],
    );
  }
}

/// A target campaign leads with a mini gauge and what is left to do.
class _TargetFace extends StatelessWidget {
  const _TargetFace({required this.progress, required this.tone});

  final CampaignTargetProgress progress;
  final SrTone tone;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SrProgressRing(
          value: progress.completionFraction,
          size: 62,
          strokeWidth: 7,
          tone: tone,
          trackColor: sr.surfaceMuted,
          center: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              EarningsCopy.progressPercentValue(progress),
              style: SrTypography.caption.copyWith(
                color: sr.tone(tone).alertText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: SrSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                EarningsCopy.progressLabel(progress.performanceScope),
                style: SrTypography.caption.copyWith(color: sr.textMuted),
              ),
              const SizedBox(height: SrSpacing.xxs),
              Text(
                EarningsCopy.progressValue(progress),
                style: SrTypography.label.copyWith(
                  color: sr.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: SrSpacing.xs),
              Text(
                // Under a team target this is the sentence that keeps a shared
                // figure from being read as a personal one, and — once it has
                // been crossed by somebody else — says so outright.
                progress.reachedByTeamWithoutMe
                    ? EarningsCopy.teamBonusAwardedElsewhere
                    : EarningsCopy.progressHeadline(progress),
                style: SrTypography.caption.copyWith(color: sr.textBody),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A scheduled campaign has no progress to draw, so it shows **when** instead.
class _ScheduledFace extends StatelessWidget {
  const _ScheduledFace({required this.offer});

  final CampaignOffer offer;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final SrToneColors tone = sr.tone(SrTone.blue);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SrSpacing.md),
      decoration: BoxDecoration(
        color: tone.fill,
        borderRadius: BorderRadius.circular(SrRadii.control),
        border: Border.all(color: tone.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            CampaignCopy.startsLabel,
            style: SrTypography.caption.copyWith(color: tone.alertText),
          ),
          const SizedBox(height: SrSpacing.xxs),
          Text(
            formatDayDate(offer.schedule.startsAt),
            style: SrTypography.sectionTitle.copyWith(color: sr.foreground),
          ),
          const SizedBox(height: SrSpacing.xs),
          Text(
            CampaignCopy.lifecycleExplanation(offer.lifecycleState),
            style: SrTypography.caption.copyWith(color: sr.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// The additive qualifiers: cap, exclusivity and how eligibility was decided.
///
/// Each is rendered **only** where the contract says so. There is no "uncapped"
/// pill and no "stackable" pill shouting about the ordinary case — a campaign
/// with nothing unusual about it shows the product count alone.
class _Qualifiers extends StatelessWidget {
  const _Qualifiers({required this.offer});

  final CampaignOffer offer;

  @override
  Widget build(BuildContext context) {
    final int? cap = offer.reward.maxRewardCoins;
    final bool snapshot =
        offer.productEligibility.resolution ==
        CampaignProductEligibilityResolution.snapshot;

    return Wrap(
      spacing: SrSpacing.xs,
      runSpacing: SrSpacing.xs,
      children: <Widget>[
        _Chip(
          icon: Icons.inventory_2_outlined,
          label: '${offer.productEligibility.eligibleProductCount}',
          tone: null,
        ),
        if (cap != null)
          _Chip(
            icon: Icons.speed_rounded,
            label: EarningsCopy.coins(cap),
            tone: SrTone.amber,
          ),
        if (offer.stackingMode.isExclusive)
          _Chip(
            icon: Icons.lock_outline_rounded,
            label: CampaignCopy.stackingLabel(offer.stackingMode),
            tone: SrTone.red,
          ),
        _Chip(
          icon: snapshot ? Icons.lock_clock_rounded : Icons.update_rounded,
          label: snapshot ? 'Snapshot' : 'Live',
          tone: SrTone.blue,
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.tone});

  final IconData icon;
  final String label;
  final SrTone? tone;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final SrToneColors? colors = tone == null ? null : sr.tone(tone!);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SrSpacing.sm,
        vertical: SrSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors?.fill ?? sr.surfaceMuted,
        borderRadius: BorderRadius.circular(SrRadii.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 11, color: colors?.foreground ?? sr.textMuted),
          const SizedBox(width: SrSpacing.xs),
          Text(
            label,
            style: SrTypography.badge.copyWith(
              color: colors?.alertText ?? sr.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
