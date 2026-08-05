import 'package:flutter/material.dart';

import '../../../../core/design/design.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../rewards/domain/entities/campaign_target_progress.dart';
import '../../../rewards/presentation/widgets/campaign_target_progress_view.dart';
import 'campaign_card.dart';
import 'campaign_copy.dart';
import 'campaign_list_cubit.dart';
import 'campaign_presentation.dart';

/// The campaign list, for whichever role supplied the state.
///
/// ## One list screen, two roles
///
/// The sections, the cards, the empty state, the stale banner and the problem
/// view are identical for both, because the only differences between the two
/// contracts are *which* campaigns arrive and whether a Vendor name is on them —
/// and both of those are already settled by the time a [CampaignPresentation]
/// exists. A Retailer Owner therefore sees up to five sections and a seller sees
/// up to two, from one implementation, with no role branch anywhere below.
///
/// ## Read-only
///
/// There is no create, edit, publish, pause, resume, version or cancel control
/// here, and no disabled one. The only interactive elements are Refresh and the
/// cards themselves.
class CampaignListBody extends StatelessWidget {
  const CampaignListBody({
    super.key,
    required this.state,
    required this.onRetry,
    required this.onOpen,
    this.progressFor,
    this.progressUnavailable = false,
  });

  final CampaignListState state;

  /// One campaign's target progress, or null when it has none.
  ///
  /// Supplied only by the Sales Staff screen: `get_my_campaign_target_progress()`
  /// is on `STAFF_EARNINGS_VIEW`, which is mapped to `SALES_STAFF` alone, so a
  /// Retailer Owner has no such contract to read and passes nothing. Null here
  /// therefore means one of two things and both render identically — this role
  /// has no progress contract, or this campaign has no target — because in
  /// neither case is there a goal to draw.
  ///
  /// The lookup is a **function of the campaign id**, never of the name: two
  /// campaigns may share a name, and only the id is the key both contracts
  /// return.
  final CampaignTargetProgress? Function(String campaignId)? progressFor;

  /// The campaigns loaded but their progress did not.
  ///
  /// Renders a banner above a list that is otherwise complete and correct. The
  /// two reads are separate contracts behind separate cubits, so one failing
  /// cannot empty the other — this flag is how the screen *says* that rather
  /// than leaving a reader to wonder where the bars went.
  final bool progressUnavailable;

  /// Re-issues the read after an outright failure.
  final VoidCallback onRetry;

  /// Opens one campaign's detail, by id.
  ///
  /// The id is an **address** the route carries to an authorized read. It is
  /// never evidence of who the caller is: both detail RPCs re-derive the
  /// Retailer from `auth.uid()` and return zero rows for an id that is not
  /// theirs.
  final void Function(String campaignId) onOpen;

  @override
  Widget build(BuildContext context) {
    // A failure with nothing loaded is the whole screen. No card renders: an
    // unreadable answer must never be shown as an empty list, and a denial must
    // never be shown as "no Vendor targets you".
    if (state.hasFailedOutright) {
      return SrRetailerProblemView(problem: state.problem!, onRetry: onRetry);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (state.isStale) ...<Widget>[
          const SrAlert(
            tone: SrAlertTone.warning,
            title: CampaignCopy.staleTitle,
            message: CampaignCopy.staleBody,
          ),
          const SizedBox(height: SrSpacing.xxl),
        ],

        // The partial-failure banner. Above the list, and never instead of it:
        // the campaigns came from a different contract and are still true.
        if (progressUnavailable) ...<Widget>[
          const SrAlert(
            tone: SrAlertTone.warning,
            title: CampaignCopy.progressUnavailableTitle,
            message: CampaignCopy.progressUnavailableBody,
          ),
          const SizedBox(height: SrSpacing.xxl),
        ],

        _Note(text: CampaignCopy.readOnlyNote(state.audience)),
        const SizedBox(height: SrSpacing.xl),

        if (state.isEmpty)
          SrEmptyState(
            icon: Icons.campaign_outlined,
            tone: SrTone.slate,
            title: CampaignCopy.emptyTitle,
            description: CampaignCopy.emptyBody(state.audience),
          )
        else ...<Widget>[
          for (final CampaignSection section in state.sections) ...<Widget>[
            SrSectionHeader(title: CampaignCopy.sectionTitle(section.kind)),
            const SizedBox(height: SrSpacing.lg),
            SrResponsiveGrid(
              // A campaign card carries a three-line reward sentence and four
              // fact chips, so it needs more room before pairing than a shop
              // card does.
              twoUpThreshold: 800,
              threeUpThreshold: 1280,
              children: <Widget>[
                for (final CampaignPresentation campaign in section.campaigns)
                  _CampaignGridItem(
                    campaign: campaign,
                    onOpen: onOpen,
                    // Joined on the campaign id, exactly as the two contracts
                    // are documented to join. Never on the name.
                    progress: progressFor?.call(campaign.offer.campaignId),
                  ),
              ],
            ),
            const SizedBox(height: SrSpacing.xxl),
          ],

          // Closes the list rather than the card, because it qualifies every
          // reward above it rather than any one of them.
          SrAlert(message: CampaignCopy.resultsNotice(state.audience)),
        ],
      ],
    );
  }
}

/// One campaign card, and its target progress when there is any.
///
/// The progress sits **beside** the card rather than inside it, and that is
/// deliberate: [CampaignCard] declares itself a single semantics node with
/// `excludeSemantics: true`, so a bar nested within it would be silent to a
/// screen reader. As a sibling it keeps its own announcement — the label, the
/// current value, the target and the state — which is what the indicator has to
/// carry to mean anything.
class _CampaignGridItem extends StatelessWidget {
  const _CampaignGridItem({
    required this.campaign,
    required this.onOpen,
    required this.progress,
  });

  final CampaignPresentation campaign;
  final void Function(String campaignId) onOpen;

  /// Null for a `PER_UNIT_COINS` campaign — which has no threshold to progress
  /// towards, so no bar is drawn — and for every campaign when the reading role
  /// has no progress contract at all.
  final CampaignTargetProgress? progress;

  @override
  Widget build(BuildContext context) {
    final CampaignTargetProgress? row = progress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CampaignCard(
          campaign: campaign,
          onTap: () => onOpen(campaign.offer.campaignId),
        ),
        if (row != null) ...<Widget>[
          const SizedBox(height: SrSpacing.sm),
          CampaignTargetProgressView(
            progress: row,
            density: CampaignProgressDensity.compact,
          ),
        ],
      ],
    );
  }
}

/// The read-only framing note.
class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: SrSpacing.xxs),
          child: ExcludeSemantics(
            child: Icon(
              Icons.info_outline_rounded,
              size: 15,
              color: sr.textMuted,
            ),
          ),
        ),
        const SizedBox(width: SrSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: SrTypography.caption.copyWith(color: sr.textMuted),
          ),
        ),
      ],
    );
  }
}
