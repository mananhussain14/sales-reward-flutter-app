import 'package:flutter/material.dart';

import '../../../../core/design/design.dart';
import '../../domain/entities/campaign_target_progress.dart';
import 'earnings_copy.dart';

/// How much of a screen a progress block is filling.
enum CampaignProgressDensity {
  /// Inside a campaign card in the list: the label, the bar, the numbers and
  /// the state, without the explanatory sentences.
  compact,

  /// On the campaign detail screen: everything, including whose sales the
  /// number counts and what the bonus means.
  full,
}

/// A `TARGET_BONUS` campaign's progress, for the seller looking at it.
///
/// ## Rendered only when the backend returned a row
///
/// A `PER_UNIT_COINS` campaign has no row in
/// `get_my_campaign_target_progress()` — there is no threshold to progress
/// towards — so no caller passes one here and no indicator is drawn. The absence
/// of a row is the whole rule; nothing on the device decides it.
///
/// ## Every claim is a stored value
///
/// The bar's fill is a display ratio. Everything that *says* something —
/// "target reached", "the bonus went to another team member", "you were awarded
/// the bonus" — comes from `target_reached` and `bonus_awarded_to_me`, two
/// booleans the database computed. Nothing is re-derived here, and the
/// difference matters: under `RETAILER_TEAM` a target can be reached by the team
/// while somebody else took the bonus, and a client that inferred payment from
/// the numbers would tell the wrong person they had been paid.
///
/// ## Text carries the state, not colour
///
/// The tone of the bar repeats what [EarningsCopy.progressStatus] already says
/// in words, and the whole block is announced as one utterance through
/// [EarningsCopy.progressSemanticLabel] — which names the label, the current
/// value, the target and the state. A bare `LinearProgressIndicator` announces a
/// percentage and nothing about whose units it counts.
class CampaignTargetProgressView extends StatelessWidget {
  const CampaignTargetProgressView({
    super.key,
    required this.progress,
    this.density = CampaignProgressDensity.full,
  });

  final CampaignTargetProgress progress;
  final CampaignProgressDensity density;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final bool isFull = density == CampaignProgressDensity.full;
    final SrToneColors tone = sr.tone(
      progress.targetReached ? SrTone.emerald : SrTone.indigo,
    );

    return Semantics(
      container: true,
      label: EarningsCopy.progressSemanticLabel(progress),
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(SrSpacing.lg),
        decoration: BoxDecoration(
          color: sr.surfaceMuted,
          borderRadius: BorderRadius.circular(SrRadii.control),
          border: Border.all(color: sr.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // -- Whose progress this is ---------------------------------------
            //
            // "Your progress" or "Team progress", never a bare percentage. A
            // team figure read as a personal one is the single most misleading
            // thing this screen could do.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  progress.performanceScope.isTeam
                      ? Icons.groups_rounded
                      : Icons.person_rounded,
                  size: 15,
                  color: sr.textMuted,
                ),
                const SizedBox(width: SrSpacing.sm),
                Expanded(
                  child: Text(
                    EarningsCopy.progressLabel(progress.performanceScope),
                    style: SrTypography.label.copyWith(color: sr.foreground),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SrSpacing.sm),

            // -- The numbers, before the bar ----------------------------------
            //
            // A reader who never sees the bar — a screen reader, a very large
            // text scale, a monochrome display — still gets both values.
            Text(
              EarningsCopy.progressValue(progress),
              style: SrTypography.bodyLarge.copyWith(color: sr.foreground),
            ),
            const SizedBox(height: SrSpacing.sm),

            ClipRRect(
              borderRadius: BorderRadius.circular(SrRadii.full),
              child: LinearProgressIndicator(
                value: progress.completionFraction,
                minHeight: 8,
                backgroundColor: sr.border,
                valueColor: AlwaysStoppedAnimation<Color>(tone.foreground),
                // The parent Semantics owns the announcement; a second one here
                // would have a reader hear a percentage after the sentence.
                semanticsLabel: null,
              ),
            ),
            const SizedBox(height: SrSpacing.sm),

            // -- The state, in words ------------------------------------------
            Text(
              EarningsCopy.progressStatus(progress),
              style: SrTypography.caption.copyWith(color: tone.alertText),
            ),

            if (isFull) ...<Widget>[
              const SizedBox(height: SrSpacing.md),
              // Whose sales count. Stated in full on the detail screen, where
              // there is room for the sentence that prevents the team figure
              // being misread.
              Text(
                EarningsCopy.progressExplanation(progress.performanceScope),
                style: SrTypography.body.copyWith(color: sr.textBody),
              ),
              const SizedBox(height: SrSpacing.sm),
              // The one sentence on this screen that makes a claim about money.
              Text(
                EarningsCopy.bonusSentence(progress),
                style: SrTypography.body.copyWith(color: sr.textBody),
              ),
            ] else if (progress.reachedByTeamWithoutMe) ...<Widget>[
              // The compact form drops the explanations — except this one.
              // "Target reached" on a card, with no further word, would read as
              // "and you were paid for it", which is exactly what is not true.
              const SizedBox(height: SrSpacing.sm),
              Text(
                EarningsCopy.teamBonusAwardedElsewhere,
                style: SrTypography.caption.copyWith(color: sr.textBody),
              ),
            ] else if (progress.targetReached &&
                progress.bonusAwardedToMe) ...<Widget>[
              const SizedBox(height: SrSpacing.sm),
              Text(
                EarningsCopy.bonusSentence(progress),
                style: SrTypography.caption.copyWith(color: sr.textBody),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
