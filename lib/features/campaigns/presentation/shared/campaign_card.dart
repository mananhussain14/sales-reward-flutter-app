import 'package:flutter/material.dart';

import '../../../../core/design/design.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/campaign_offer.dart';
import '../../domain/entities/campaign_reward.dart';
import 'campaign_copy.dart';
import 'campaign_empty_products_notice.dart';
import 'campaign_presentation.dart';
import 'campaign_status_badge.dart';

/// One campaign in a list, for either role.
///
/// ## Identity, then offer, then facts
///
/// The card is read top to bottom in the order the questions are asked. *What
/// is this and is it running?* — a type disc, the name, the status pill and the
/// rule pill. *What does it pay?* — the reward sentence, on its own recessed
/// panel, because it is the single most important thing on the card and a
/// paragraph among four chips does not read as important. *On what terms?* — the
/// scope, the eligible-product count, the exclusivity and the dates, as chips.
///
/// ## The accent is the campaign type, and it is the only accent
///
/// A per-unit campaign carries an indigo bolt; a target campaign carries a blue
/// flag. That is one tinted disc and one pill per card — not a gradient, not a
/// coloured border and not a tinted surface. A list where every card is filled
/// has no hierarchy left to spend, which is exactly the flatness this redesign
/// exists to fix.
///
/// ## The whole card is the tap target
///
/// [SrCard.onTap] wraps the entire surface in an `InkWell`, so the target is the
/// card's own area — far beyond the 48dp minimum on every surface this app runs
/// on — rather than a chevron or a title link a thumb has to find. The chevron
/// is an affordance, not the target, and [SrPressScale] acknowledges the press
/// on the whole surface without entering the gesture arena the `InkWell` owns.
///
/// ## One semantic label, in visual order
///
/// The card announces itself as a single button whose label is
/// [CampaignCopy.cardSemanticLabel], and `excludeSemantics` drops its children
/// from the tree. Without that, a reader would hear the name, then the status
/// pill, then the Vendor, then each fact chip, then the warning — a dozen nodes
/// for one card — and the tap target would be ambiguous.
///
/// ## No progress and no balance on the card itself
///
/// There is no ring, no percentage, no units-sold figure and no coin total in
/// here, because the campaign contract returns none. A seller's target progress
/// is a **second** contract on a **second** permission and is rendered as a
/// sibling beneath the card, where it keeps its own announcement.
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

  /// The tone and glyph for a campaign's rule type.
  ///
  /// Deliberately **not** emerald: emerald means "target reached" on the
  /// progress indicator directly below this card, and reusing it for "this is a
  /// target campaign" would have one colour mean two things a few pixels apart.
  static (SrTone, IconData) accentFor(CampaignReward reward) =>
      switch (reward) {
        CampaignPerUnitReward() => (SrTone.indigo, Icons.bolt_rounded),
        CampaignTargetReward() => (SrTone.blue, Icons.flag_rounded),
      };

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final CampaignOffer offer = campaign.offer;
    final (SrTone accentTone, IconData accentIcon) = accentFor(offer.reward);
    final int? cap = offer.reward.maxRewardCoins;

    return Semantics(
      button: true,
      label: CampaignCopy.cardSemanticLabel(campaign),
      excludeSemantics: true,
      child: SrPressScale(
        child: SrCard(
          variant: SrCardVariant.interactive,
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // -- Type, name, status, and the tap affordance -----------------
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SrIconDisc(icon: accentIcon, tone: accentTone, size: 40),
                  const SizedBox(width: SrSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          offer.name,
                          style: SrTypography.cardTitle.copyWith(
                            color: sr.foreground,
                          ),
                          // Bounded rather than clipped: a 150-character
                          // campaign name is legal in the schema, and two lines
                          // with an ellipsis keeps every card the same shape
                          // without the name overflowing its row at any text
                          // scale.
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: SrSpacing.sm),
                        // The two pills wrap rather than share a fixed row, so
                        // a long status and a long rule name never compete for
                        // one line at a large text scale.
                        Wrap(
                          spacing: SrSpacing.sm,
                          runSpacing: SrSpacing.sm,
                          children: <Widget>[
                            CampaignStatusBadge(state: offer.lifecycleState),
                            SrBadge(
                              label: CampaignCopy.rewardTypeLabel(offer.reward),
                              tone: accentTone,
                              icon: accentIcon,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: SrSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.only(top: SrSpacing.smPlus),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: sr.textMuted,
                    ),
                  ),
                ],
              ),

              // -- Vendor, when the contract returns one ----------------------
              //
              // Omitted entirely for a seller. Never rendered as an empty row
              // or a placeholder: the staff contract withholds the Vendor by
              // design, and a blank "Vendor:" line would advertise a value
              // being hidden.
              if (campaign.vendorName != null) ...<Widget>[
                const SizedBox(height: SrSpacing.md),
                Text(
                  '${CampaignCopy.vendorLabel} · ${campaign.vendorName}',
                  style: SrTypography.caption.copyWith(color: sr.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // -- The offer, given its own surface ---------------------------
              const SizedBox(height: SrSpacing.lg),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(SrSpacing.md),
                decoration: BoxDecoration(
                  color: sr.surfaceMuted,
                  borderRadius: BorderRadius.circular(SrRadii.control),
                  border: Border.all(color: sr.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: SrSpacing.xxs),
                      child: Icon(
                        Icons.monetization_on_outlined,
                        size: 16,
                        color: sr.tone(accentTone).foreground,
                      ),
                    ),
                    const SizedBox(width: SrSpacing.sm),
                    Expanded(
                      child: Text(
                        CampaignCopy.rewardSentence(offer, campaign.audience),
                        style: SrTypography.body.copyWith(
                          color: sr.foreground,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // -- The facts ---------------------------------------------------
              //
              // A Wrap rather than a Row: five chips at a large text scale on a
              // narrow phone would overflow a single line, and wrapping is the
              // behaviour that keeps every one of them readable instead of
              // shrinking them all.
              const SizedBox(height: SrSpacing.md),
              Wrap(
                spacing: SrSpacing.sm,
                runSpacing: SrSpacing.sm,
                children: <Widget>[
                  _Fact(
                    icon: offer.performanceScope.isTeam
                        ? Icons.groups_rounded
                        : Icons.person_rounded,
                    label: CampaignCopy.measurementLabel(
                      offer.performanceScope,
                    ),
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
                  // The campaign ceiling, and ONLY when the contract exposes
                  // one. There is no "uncapped" chip: absence of a cap is the
                  // ordinary case, and naming it would invent a term.
                  if (cap != null)
                    _Fact(
                      icon: Icons.speed_rounded,
                      label: CampaignCopy.campaignMaximumLabel(cap),
                    ),
                ],
              ),

              // -- The truthful zero state -------------------------------------
              if (offer.showsEmptyProductWarning) ...<Widget>[
                const SizedBox(height: SrSpacing.md),
                const CampaignCardEmptyProductsNote(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One icon-and-label fact chip.
///
/// The icon is decorative — every chip's meaning is in its text, and the card's
/// single semantic label carries all of them — so it is excluded from the
/// semantics tree by the card above rather than given a label of its own.
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
        color: sr.surface,
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
