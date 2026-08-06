import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../campaigns/domain/entities/campaign_offer.dart';
import '../../../../campaigns/domain/entities/campaign_reward.dart';
import '../../../../campaigns/presentation/shared/campaign_card.dart';
import '../../../../campaigns/presentation/shared/campaign_copy.dart';
import '../../../../campaigns/presentation/shared/campaign_presentation.dart';
import '../../../../campaigns/presentation/shared/campaign_status_badge.dart';
import '../../../../rewards/domain/entities/campaign_target_progress.dart';
import '../../../../rewards/presentation/widgets/earnings_copy.dart';
import 'sales_staff_home_copy.dart';
import 'sales_staff_opportunity.dart';

/// The Sales Staff home's focal point: one campaign, how far along it is, and
/// what reaching it pays.
///
/// ## Why a hero at all
///
/// The first version of this screen led with a coin total. That answers "what
/// have I already done?" — a reasonable question, but not the one somebody
/// standing behind a counter at the start of a shift is asking. This card
/// answers the five the redesign named, in the order they are asked: what is
/// the opportunity, how close am I, what does it pay, what do I do next, and
/// where do I submit.
///
/// ## The gauge is a drawing; the numbers are the facts
///
/// [SrProgressRing] receives [CampaignTargetProgress.completionFraction], which
/// is already clamped, and the real numerator and denominator are printed
/// beside it. A seller at 5 units against a target of 3 sees a full ring **and**
/// `5 of 3 units`: the drawing saturates, the facts do not, and nothing here
/// rounds one to match the other.
///
/// The colour transition is a function of the same clamped fraction and of
/// `target_reached` — never of anything this widget decides. Early progress is
/// violet, the approach to a target warms towards amber, and a reached target
/// is emerald. A reader who cannot resolve any of those still has the
/// percentage, the units, the status pill and the sentence.
///
/// ## Nothing on it is a promise
///
/// The remaining-units line and the configured reward are stored values. The
/// action opens the campaign; it does not claim a reward is coming.
class SalesStaffNextRewardHero extends StatelessWidget {
  const SalesStaffNextRewardHero({
    super.key,
    required this.opportunity,
    required this.onView,
  });

  final SalesStaffOpportunity opportunity;

  /// Opens this campaign's detail.
  final VoidCallback onView;

  /// The gauge's colours for a progress state.
  ///
  /// Read from the tone ramp rather than hand-mixed, so the gauge cannot drift
  /// away from the palette the rest of the product uses.
  static List<Color> _sweepFor(
    SrColorScheme sr,
    CampaignTargetProgress? progress,
  ) {
    if (progress == null) {
      return <Color>[sr.tone(SrTone.blue).foreground, sr.brand];
    }
    if (progress.targetReached) {
      return <Color>[
        sr.tone(SrTone.blue).foreground,
        sr.tone(SrTone.emerald).foreground,
      ];
    }
    // Warms as the fraction rises. The threshold is a presentation choice about
    // colour and decides nothing: `target_reached` remains the only statement
    // that a target has been met.
    if (progress.completionFraction >= 0.6) {
      return <Color>[sr.brand, sr.tone(SrTone.amber).foreground];
    }
    return <Color>[sr.tone(SrTone.blue).foreground, sr.brand];
  }

  static SrTone _toneFor(CampaignTargetProgress? progress) {
    if (progress == null) {
      return SrTone.indigo;
    }
    return progress.targetReached ? SrTone.emerald : SrTone.indigo;
  }

  String _eyebrow() {
    final CampaignTargetProgress? row = opportunity.progress;
    if (row != null) {
      return row.targetReached
          ? SalesStaffHomeCopy.heroEyebrowReached
          : SalesStaffHomeCopy.heroEyebrowNext;
    }
    return opportunity.isRunning
        ? SalesStaffHomeCopy.heroEyebrowRunning
        : SalesStaffHomeCopy.heroEyebrowUpcoming;
  }

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final CampaignOffer offer = opportunity.campaign.offer;
    final CampaignTargetProgress? row = opportunity.progress;
    final SrTone tone = _toneFor(row);
    final (SrTone accentTone, IconData accentIcon) = CampaignCard.accentFor(
      offer.reward,
    );

    return Semantics(
      container: true,
      label: _semanticLabel(),
      excludeSemantics: true,
      child: SrPressScale(
        child: SrFeatureCard(
          tone: tone,
          onTap: onView,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // -- Eyebrow and status -------------------------------------
              Row(
                children: <Widget>[
                  Icon(
                    row?.targetReached ?? false
                        ? Icons.emoji_events_rounded
                        : Icons.auto_awesome_rounded,
                    size: 14,
                    color: sr.tone(tone).foreground,
                  ),
                  const SizedBox(width: SrSpacing.sm),
                  Expanded(
                    child: Text(
                      _eyebrow(),
                      style: SrTypography.eyebrow.copyWith(
                        color: sr.tone(tone).alertText,
                      ),
                    ),
                  ),
                  CampaignStatusBadge(state: offer.lifecycleState),
                ],
              ),
              const SizedBox(height: SrSpacing.md),

              // -- The campaign ---------------------------------------------
              Text(
                offer.name,
                style: SrTypography.screenTitle.copyWith(color: sr.foreground),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: SrSpacing.sm),
              Wrap(
                spacing: SrSpacing.sm,
                runSpacing: SrSpacing.sm,
                children: <Widget>[
                  SrBadge(
                    label: CampaignCopy.rewardTypeLabel(offer.reward),
                    tone: accentTone,
                    icon: accentIcon,
                  ),
                  SrBadge(
                    label: CampaignCopy.measurementLabel(
                      offer.performanceScope,
                    ),
                    icon: offer.performanceScope.isTeam
                        ? Icons.groups_rounded
                        : Icons.person_rounded,
                  ),
                ],
              ),
              const SizedBox(height: SrSpacing.xl),

              // -- The gauge, or the offer when there is no target -----------
              if (row != null)
                _TargetBlock(progress: row, sweep: _sweepFor(sr, row))
              else
                _OfferBlock(
                  offer: offer,
                  audience: opportunity.campaign.audience,
                ),

              const SizedBox(height: SrSpacing.lg),
              // Left-aligned and content-width, not a full-width slab. The
              // whole card is already the tap target; this is the visible
              // affordance for it, and keeping it to the left leaves the
              // bottom-right of the screen to the floating Add receipt pill so
              // the two controls never overlap.
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: SrButton(
                  label: SalesStaffHomeCopy.heroAction,
                  icon: Icons.arrow_forward_rounded,
                  variant: SrButtonVariant.secondary,
                  onPressed: onView,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The whole card as one utterance, in visual order.
  String _semanticLabel() {
    final CampaignOffer offer = opportunity.campaign.offer;
    final CampaignTargetProgress? row = opportunity.progress;
    final StringBuffer buffer = StringBuffer(_eyebrow())
      ..write('. ')
      ..write(offer.name)
      ..write('. ')
      ..write(CampaignCopy.lifecycleLabel(offer.lifecycleState))
      ..write('. ')
      ..write(CampaignCopy.rewardSentence(offer, opportunity.campaign.audience))
      ..write(' ');

    if (row != null) {
      buffer.write(EarningsCopy.progressSemanticLabel(row));
    }
    return buffer.toString();
  }
}

/// The gauge, the real numbers, and the one encouraging sentence.
class _TargetBlock extends StatelessWidget {
  const _TargetBlock({required this.progress, required this.sweep});

  final CampaignTargetProgress progress;
  final List<Color> sweep;

  /// Below this width the gauge and the facts stack, which is what keeps both
  /// readable at a large text scale on a narrow phone.
  static const double _sideBySide = 300;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final SrTone tone = progress.targetReached ? SrTone.emerald : SrTone.indigo;

    final Widget gauge = SrProgressRing(
      value: progress.completionFraction,
      size: 148,
      strokeWidth: 14,
      tone: tone,
      gradient: sweep,
      ticks: 36,
      glow: true,
      trackColor: sr.surfaceMuted,
      center: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              EarningsCopy.progressPercentValue(progress),
              style: SrTypography.statValue.copyWith(
                color: sr.tone(tone).alertText,
              ),
            ),
            Text(
              SalesStaffHomeCopy.heroOfTarget,
              style: SrTypography.caption.copyWith(color: sr.textMuted),
            ),
          ],
        ),
      ),
    );

    final Widget facts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              progress.performanceScope.isTeam
                  ? Icons.groups_rounded
                  : Icons.person_rounded,
              size: 14,
              color: sr.textMuted,
            ),
            const SizedBox(width: SrSpacing.xs),
            Flexible(
              child: Text(
                EarningsCopy.progressLabel(progress.performanceScope),
                style: SrTypography.caption.copyWith(color: sr.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: SrSpacing.xs),
        // The numerator and denominator, at headline weight. They are never
        // replaced by the percentage inside the gauge.
        Text(
          EarningsCopy.progressValue(progress),
          style: SrTypography.sectionTitle.copyWith(color: sr.foreground),
        ),
        const SizedBox(height: SrSpacing.sm),
        Text(
          EarningsCopy.progressHeadline(progress),
          style: SrTypography.body.copyWith(color: sr.textBody),
        ),
        const SizedBox(height: SrSpacing.md),
        SrStatPill(
          label: EarningsCopy.configuredBonusLabel,
          value: EarningsCopy.coins(progress.configuredRewardCoins),
          icon: Icons.emoji_events_outlined,
          tone: SrTone.amber,
        ),
      ],
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < _sideBySide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(child: gauge),
              const SizedBox(height: SrSpacing.lg),
              facts,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            gauge,
            const SizedBox(width: SrSpacing.xl),
            Expanded(child: facts),
          ],
        );
      },
    );
  }
}

/// What a campaign with no target offers, for a hero that has no gauge to draw.
class _OfferBlock extends StatelessWidget {
  const _OfferBlock({required this.offer, required this.audience});

  final CampaignOffer offer;
  final CampaignAudience audience;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final int? cap = offer.reward.maxRewardCoins;
    final CampaignReward reward = offer.reward;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          CampaignCopy.rewardSentence(offer, audience),
          style: SrTypography.bodyLarge.copyWith(color: sr.foreground),
        ),
        const SizedBox(height: SrSpacing.lg),
        Wrap(
          spacing: SrSpacing.sm,
          runSpacing: SrSpacing.sm,
          children: <Widget>[
            if (reward is CampaignPerUnitReward)
              SrStatPill(
                label: 'Per eligible unit',
                value: EarningsCopy.coins(reward.coinsPerUnit),
                icon: Icons.bolt_rounded,
                tone: SrTone.indigo,
              ),
            SrStatPill(
              label: 'Eligible products',
              value: '${offer.productEligibility.eligibleProductCount}',
              icon: Icons.inventory_2_outlined,
            ),
            if (cap != null)
              SrStatPill(
                label: 'Campaign maximum',
                value: EarningsCopy.coins(cap),
                icon: Icons.speed_rounded,
                tone: SrTone.amber,
              ),
          ],
        ),
      ],
    );
  }
}
