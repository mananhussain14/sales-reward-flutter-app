import 'package:flutter/material.dart';

import '../../../../core/design/design.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/campaign_target_progress.dart';
import 'earnings_copy.dart';

/// How much of a screen a progress block is filling.
enum CampaignProgressDensity {
  /// Inside a campaign card in the list: the ring, the numbers, the state and
  /// the one encouraging line, without the explanatory sentences.
  compact,

  /// On the campaign detail screen and the Sales Staff home: everything,
  /// including whose sales the number counts and what the bonus means.
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
/// The ring's sweep is a display ratio. Everything that *says* something —
/// "target reached", "the bonus went to another team member", "you were awarded
/// the bonus" — comes from `target_reached` and `bonus_awarded_to_me`, two
/// booleans the database computed. Nothing is re-derived here, and the
/// difference matters: under `RETAILER_TEAM` a target can be reached by the team
/// while somebody else took the bonus, and a client that inferred payment from
/// the numbers would tell the wrong person they had been paid.
///
/// ## The ring never hides the numbers
///
/// `12 of 25 units` sits beside the ring at every density, and the percentage
/// inside it is the clamped ratio. When 30 units have been counted against a
/// target of 25 the ring rests at full and the text still reads `30 of 25
/// units` — the drawing saturates, the facts do not.
///
/// ## Text carries the state, not colour
///
/// The tone of the ring repeats what [EarningsCopy.progressStatus] already says
/// in words, and the whole block is announced as one utterance through
/// [EarningsCopy.progressSemanticLabel] — which names the label, the current
/// value, the target, the percentage and the state.
class CampaignTargetProgressView extends StatelessWidget {
  const CampaignTargetProgressView({
    super.key,
    required this.progress,
    this.density = CampaignProgressDensity.full,
  });

  final CampaignTargetProgress progress;
  final CampaignProgressDensity density;

  /// Below this width the ring and the text stack instead of sitting side by
  /// side — which is what keeps both readable at a 200% text scale on a narrow
  /// phone.
  static const double _sideBySideWidth = 340;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final bool isFull = density == CampaignProgressDensity.full;
    final SrTone toneName = progress.targetReached
        ? SrTone.emerald
        : SrTone.indigo;
    final SrToneColors tone = sr.tone(toneName);
    final double ringSize = isFull ? 132 : 96;

    final Widget ring = SrProgressRing(
      value: progress.completionFraction,
      size: ringSize,
      strokeWidth: isFull ? 11 : 9,
      tone: toneName,
      center: _RingCentre(progress: progress, tone: tone, compact: !isFull),
    );

    final Widget facts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // -- Whose progress this is ---------------------------------------
        //
        // "Your progress" or "Team progress", never a bare percentage. A team
        // figure read as a personal one is the single most misleading thing
        // this screen could do.
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
            Flexible(
              child: Text(
                EarningsCopy.progressLabel(progress.performanceScope),
                style: SrTypography.label.copyWith(color: sr.foreground),
              ),
            ),
          ],
        ),
        const SizedBox(height: SrSpacing.sm),

        // -- The real numbers ----------------------------------------------
        //
        // A reader who never sees the ring — a screen reader, a very large text
        // scale, a monochrome display — still gets both values.
        Text(
          EarningsCopy.progressValue(progress),
          style: SrTypography.bodyLarge.copyWith(color: sr.foreground),
        ),
        const SizedBox(height: SrSpacing.xs),

        // -- The state, in words, on a chip that is never the only channel ---
        _StatusChip(
          label: EarningsCopy.progressStatus(progress),
          tone: tone,
          icon: progress.targetReached
              ? Icons.check_circle_rounded
              : Icons.trending_up_rounded,
        ),
        const SizedBox(height: SrSpacing.sm),

        // -- The encouraging line, which is still a statement of fact --------
        Text(
          EarningsCopy.progressHeadline(progress),
          style: SrTypography.body.copyWith(color: sr.textBody),
        ),
      ],
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
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                if (constraints.maxWidth < _sideBySideWidth) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Center(child: ring),
                      const SizedBox(height: SrSpacing.lg),
                      facts,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    ring,
                    const SizedBox(width: SrSpacing.xl),
                    Expanded(child: facts),
                  ],
                );
              },
            ),

            if (isFull) ...<Widget>[
              const SizedBox(height: SrSpacing.lg),
              Divider(height: 1, color: sr.border),
              const SizedBox(height: SrSpacing.lg),
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

/// What sits inside the ring: the percentage, and the word that stops it being
/// read as anything else.
class _RingCentre extends StatelessWidget {
  const _RingCentre({
    required this.progress,
    required this.tone,
    required this.compact,
  });

  final CampaignTargetProgress progress;
  final SrToneColors tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            EarningsCopy.progressPercentValue(progress),
            style:
                (compact ? SrTypography.sectionTitle : SrTypography.statValue)
                    .copyWith(color: tone.alertText),
          ),
          if (!compact) ...<Widget>[
            const SizedBox(height: SrSpacing.xxs),
            Text(
              'of target',
              style: SrTypography.caption.copyWith(color: sr.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// The state, as a chip carrying an icon **and** a word.
///
/// Two channels rather than one: the milestone forbids communicating campaign
/// status by colour alone, and a reader in monochrome still gets the tick and
/// the sentence.
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.tone,
    required this.icon,
  });

  final String label;
  final SrToneColors tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SrSpacing.smPlus,
        vertical: SrSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tone.fill,
        borderRadius: BorderRadius.circular(SrRadii.full),
        border: Border.all(color: tone.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: tone.foreground),
          const SizedBox(width: SrSpacing.xs),
          Flexible(
            child: Text(
              label,
              style: SrTypography.badge.copyWith(color: tone.alertText),
            ),
          ),
        ],
      ),
    );
  }
}
