import 'package:flutter/material.dart';

import '../../../../core/design/design.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/campaign_lifecycle_state.dart';
import 'campaign_copy.dart';
import 'campaign_presentation.dart';
import 'campaign_status_badge.dart';

/// The heading above one group of campaigns.
///
/// ## Why not `SrSectionHeader`
///
/// That widget is a title, an optional description and an optional action, and
/// it is right almost everywhere. It is not right here, because the problem this
/// screen had was that two adjacent lists of near-identical cards were
/// distinguishable only by two words of heading.
///
/// This carries the group's **own** glyph and tone — the same pair every status
/// pill on the cards beneath it uses, read from
/// [CampaignStatusBadge.toneFor] and [CampaignStatusBadge.iconFor] rather than
/// chosen again here — plus a count and a line saying what belonging to the
/// group means for a sale. Three channels, and the tone is never one of the
/// necessary ones.
///
/// ## One announcement
///
/// Marked as a header and spoken as a single utterance: the title, the count and
/// the consequence, in the order they are drawn.
class CampaignSectionHeading extends StatelessWidget {
  const CampaignSectionHeading({
    super.key,
    required this.kind,
    required this.count,
  });

  final CampaignSectionKind kind;

  /// How many campaigns are in this group. Always the real number: the list
  /// never truncates a section, so this cannot disagree with what is below it.
  final int count;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final CampaignLifecycleState state = CampaignCopy.sectionState(kind);
    final SrTone tone = CampaignStatusBadge.toneFor(state);

    return Semantics(
      header: true,
      container: true,
      label:
          '${CampaignCopy.sectionTitle(kind)}. '
          '${CampaignCopy.sectionCount(count)}. '
          '${CampaignCopy.sectionDescription(kind)}',
      excludeSemantics: true,
      // A tinted banner rather than a bare row. Two adjacent groups of similar
      // cards need a divider a reader cannot miss, and a heading floating on
      // the page background is not one.
      child: Container(
        padding: const EdgeInsets.all(SrSpacing.md),
        decoration: BoxDecoration(
          color: sr.tone(tone).fill,
          borderRadius: BorderRadius.circular(SrRadii.surface),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SrIconDisc(
              icon: CampaignStatusBadge.iconFor(state),
              tone: tone,
              size: 40,
            ),
            const SizedBox(width: SrSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // A Wrap rather than a Row: at a large text scale the title and
                  // the count do not share a line, and wrapping keeps both
                  // readable instead of ellipsising the title.
                  Wrap(
                    spacing: SrSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text(
                        CampaignCopy.sectionTitle(kind),
                        style: SrTypography.sectionTitle.copyWith(
                          color: sr.foreground,
                        ),
                      ),
                      Text(
                        CampaignCopy.sectionCount(count),
                        style: SrTypography.caption.copyWith(
                          color: sr.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: SrSpacing.xxs),
                  Text(
                    CampaignCopy.sectionDescription(kind),
                    style: SrTypography.body.copyWith(color: sr.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
