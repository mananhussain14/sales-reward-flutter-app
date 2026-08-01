import 'package:flutter/material.dart';

import '../../../../core/design/design.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/campaign_offer.dart';
import 'campaign_copy.dart';
import 'campaign_empty_products_notice.dart';
import 'campaign_presentation.dart';
import 'campaign_status_badge.dart';

/// One campaign in a list, for either role.
///
/// ## The whole card is the tap target
///
/// [SrCard.onTap] wraps the entire surface in an `InkWell`, so the target is the
/// card's own area — far beyond the 48dp minimum on every surface this app runs
/// on — rather than a chevron or a title link a thumb has to find. The chevron
/// is an affordance, not the target.
///
/// ## One semantic label, in visual order
///
/// The card announces itself as a single button whose label is
/// [CampaignCopy.cardSemanticLabel], and `excludeSemantics` drops its children
/// from the tree. Without that, a reader would hear the name, then the status
/// pill, then the Vendor, then each fact tile, then the warning — a dozen nodes
/// for one card — and the tap target would be ambiguous.
///
/// The label is assembled in the same order as the visible content, so the
/// spoken order follows the layout.
///
/// ## No progress and no balance
///
/// There is no bar, no percentage, no units-sold figure and no coin total on
/// this card, because the contract returns none and there is nothing to compute
/// one from. What is shown is the **offer**: how it pays, how it is measured,
/// what counts, and when. The list screen states once that results arrive with
/// the calculation engine.
///
/// ## Nothing here is a control
///
/// No edit, no publish, no pause, no resume, no version, no cancel — and not a
/// disabled one either. Every one of those is a Vendor operation on
/// `CAMPAIGNS_MANAGE`, and an affordance would be a promise nothing in this
/// application could keep.
class CampaignCard extends StatelessWidget {
  const CampaignCard({super.key, required this.campaign, required this.onTap});

  final CampaignPresentation campaign;

  /// Opens the detail screen. Required rather than nullable: a card that did
  /// not navigate would still look tappable, and the whole card is the target.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final CampaignOffer offer = campaign.offer;

    return Semantics(
      button: true,
      label: CampaignCopy.cardSemanticLabel(campaign),
      excludeSemantics: true,
      child: SrCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // -- Name, status, and the tap affordance -----------------------
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    offer.name,
                    style: SrTypography.cardTitle.copyWith(
                      color: sr.foreground,
                    ),
                    // Bounded rather than clipped: a 150-character campaign
                    // name is legal in the schema, and two lines with an
                    // ellipsis keeps every card the same shape without the
                    // name overflowing its row at any text scale.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: SrSpacing.md),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: sr.textMuted,
                ),
              ],
            ),
            const SizedBox(height: SrSpacing.sm),

            // The badge sits in its own row rather than beside the name, so a
            // long name and a long status never compete for one line.
            Align(
              alignment: Alignment.centerLeft,
              child: CampaignStatusBadge(state: offer.lifecycleState),
            ),

            // -- Vendor, when the contract returns one ----------------------
            //
            // Omitted entirely for a seller. Never rendered as an empty row or
            // a placeholder: the staff contract withholds the Vendor by design,
            // and a blank "Vendor:" line would advertise a value being hidden.
            if (campaign.vendorName != null) ...<Widget>[
              const SizedBox(height: SrSpacing.md),
              Text(
                '${CampaignCopy.vendorLabel} · ${campaign.vendorName}',
                style: SrTypography.caption.copyWith(color: sr.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // -- The offer, in one sentence ---------------------------------
            const SizedBox(height: SrSpacing.md),
            Text(
              CampaignCopy.rewardSentence(offer, campaign.audience),
              style: SrTypography.body.copyWith(color: sr.textBody),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),

            // -- The facts ---------------------------------------------------
            //
            // A Wrap rather than a Row: four chips at a large text scale on a
            // narrow phone would overflow a single line, and wrapping is the
            // behaviour that keeps every one of them readable instead of
            // shrinking them all.
            const SizedBox(height: SrSpacing.lg),
            Wrap(
              spacing: SrSpacing.sm,
              runSpacing: SrSpacing.sm,
              children: <Widget>[
                _Fact(
                  icon: offer.performanceScope.isTeam
                      ? Icons.groups_rounded
                      : Icons.person_rounded,
                  label: CampaignCopy.measurementLabel(offer.performanceScope),
                ),
                _Fact(
                  icon: Icons.inventory_2_outlined,
                  label: CampaignCopy.productCountLabel(
                    offer.productEligibility.eligibleProductCount,
                  ),
                ),
                _Fact(
                  icon: offer.stackingMode.isExclusive
                      ? Icons.lock_outline_rounded
                      : Icons.layers_outlined,
                  label: CampaignCopy.stackingLabel(offer.stackingMode),
                ),
                _Fact(
                  icon: Icons.date_range_outlined,
                  label: CampaignCopy.dateRange(offer.schedule),
                ),
              ],
            ),

            // -- The truthful zero state -------------------------------------
            if (offer.showsEmptyProductWarning) ...<Widget>[
              const SizedBox(height: SrSpacing.lg),
              const CampaignCardEmptyProductsNote(),
            ],
          ],
        ),
      ),
    );
  }
}

/// One icon-and-label fact chip.
///
/// The icon is decorative — every chip's meaning is in its text, and the card's
/// single semantic label carries all four — so it is excluded from the semantics
/// tree by the card above rather than given a label of its own.
class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SrSpacing.smPlus,
        vertical: SrSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: sr.surfaceMuted,
        borderRadius: BorderRadius.circular(SrRadii.sm),
        border: Border.all(color: sr.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: sr.textMuted),
          const SizedBox(width: SrSpacing.xs),
          // Constrained so a long date range or a wide text scale wraps inside
          // the chip instead of pushing the row past the card's edge.
          Flexible(
            child: Text(
              label,
              style: SrTypography.caption.copyWith(color: sr.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
