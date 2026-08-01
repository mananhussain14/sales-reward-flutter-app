import 'package:flutter/material.dart';

import '../../../../core/design/design.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/campaign_offer.dart';
import '../../domain/entities/campaign_product.dart';
import 'campaign_copy.dart';
import 'campaign_empty_products_notice.dart';
import 'campaign_presentation.dart';
import 'campaign_status_badge.dart';

/// One campaign, read-only, for either role.
///
/// ## The order is the argument
///
/// Status first, because everything below it is conditional on whether the
/// campaign is running. Then what it is and who runs it. Then the warning, if
/// there is one — **above** the reward, so nobody reads "earn 10 coins per unit"
/// before learning that nothing they stock is eligible. Then how it pays, how it
/// is measured, what counts, when, and how it interacts with other campaigns.
/// The calculation-engine notice closes, where a reader who has just read four
/// reward facts is about to wonder where the numbers are.
///
/// ## Read-only, with no controls of any kind
///
/// No edit, publish, pause, resume, version or cancel — and none disabled. Every
/// one is a Vendor operation on `CAMPAIGNS_MANAGE`, exercised on the Web, and no
/// such RPC is named anywhere in this application. The same widget serves both
/// roles precisely because neither has an action: there is no branch here that
/// could grow one for one role and not the other.
///
/// ## And no progress
///
/// No bar, no percentage, no units sold, no coins earned, no claim. The contract
/// returns the offer; [CampaignCopy.engineNotice] says the rest is not connected
/// yet, which is the honest form of an absent number.
class CampaignDetailView extends StatelessWidget {
  const CampaignDetailView({
    super.key,
    required this.campaign,
    required this.products,
  });

  final CampaignPresentation campaign;

  /// The products this campaign counts **for this Retailer**, from
  /// `list_my_*_campaign_products()`.
  ///
  /// May be empty while the campaign exists — the zero-eligible-product state.
  /// It is never a failure: a failed product read never reaches this widget,
  /// because the repository reports it as a failure rather than as an empty
  /// list.
  final List<CampaignProduct> products;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final CampaignOffer offer = campaign.offer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // -- 1 & 2. Status, name, Vendor ---------------------------------
        Align(
          alignment: Alignment.centerLeft,
          child: CampaignStatusBadge(state: offer.lifecycleState),
        ),
        const SizedBox(height: SrSpacing.md),
        Text(
          offer.name,
          style: SrTypography.screenTitle.copyWith(color: sr.foreground),
        ),
        if (campaign.vendorName != null) ...<Widget>[
          const SizedBox(height: SrSpacing.xs),
          Text(
            '${CampaignCopy.vendorLabel} · ${campaign.vendorName}',
            style: SrTypography.body.copyWith(color: sr.textSecondary),
          ),
        ],
        const SizedBox(height: SrSpacing.sm),
        // The state as a sentence as well as a pill, so the status is never
        // carried by a coloured chip alone.
        Text(
          CampaignCopy.lifecycleExplanation(offer.lifecycleState),
          style: SrTypography.body.copyWith(color: sr.textBody),
        ),

        // -- 3. Description ------------------------------------------------
        //
        // Nullable in the schema. Absent means the section is not rendered, not
        // that a placeholder appears: an empty card with a heading would look
        // like something failed to load.
        if (offer.description != null) ...<Widget>[
          const SizedBox(height: SrSpacing.xxl),
          SrSectionCard(
            title: CampaignCopy.descriptionSectionTitle,
            child: Text(
              offer.description!,
              style: SrTypography.body.copyWith(color: sr.textBody),
            ),
          ),
        ],

        // -- 4. The important eligibility warning ---------------------------
        //
        // Above the reward on purpose. See the class doc.
        if (offer.showsEmptyProductWarning) ...<Widget>[
          const SizedBox(height: SrSpacing.xxl),
          const CampaignEmptyProductsNotice(),
        ],

        // -- 5. Reward ------------------------------------------------------
        const SizedBox(height: SrSpacing.xxl),
        SrSectionCard(
          title: CampaignCopy.rewardSectionTitle,
          child: Text(
            CampaignCopy.rewardSentence(offer, campaign.audience),
            style: SrTypography.bodyLarge.copyWith(color: sr.foreground),
          ),
        ),

        // -- 6. Performance measurement --------------------------------------
        const SizedBox(height: SrSpacing.xxl),
        SrSectionCard(
          title: CampaignCopy.measurementSectionTitle,
          child: _IconLine(
            icon: offer.performanceScope.isTeam
                ? Icons.groups_rounded
                : Icons.person_rounded,
            text: CampaignCopy.measurementSentence(
              offer.performanceScope,
              campaign.audience,
            ),
          ),
        ),

        // -- 7. Eligible products --------------------------------------------
        const SizedBox(height: SrSpacing.xxl),
        SrSectionCard(
          title: CampaignCopy.productsSectionTitle,
          // The rule, then the count, then the products themselves. The rule
          // first because it is what makes the count mean anything: "3
          // products" reads differently under a frozen snapshot than under a
          // live assignment set.
          description: CampaignCopy.eligibilitySentence(
            offer.productEligibility.scope,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                CampaignCopy.productCountLabel(
                  offer.productEligibility.eligibleProductCount,
                ),
                style: SrTypography.label.copyWith(color: sr.foreground),
              ),
              if (products.isEmpty) ...<Widget>[
                const SizedBox(height: SrSpacing.sm),
                Text(
                  CampaignCopy.productsEmptyDetail,
                  style: SrTypography.body.copyWith(color: sr.textMuted),
                ),
              ] else ...<Widget>[
                const SizedBox(height: SrSpacing.lg),
                for (final CampaignProduct product in products)
                  _ProductRow(product: product),
              ],
            ],
          ),
        ),

        // -- 8. Schedule -------------------------------------------------------
        const SizedBox(height: SrSpacing.xxl),
        SrSectionCard(
          title: CampaignCopy.scheduleSectionTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Fact(
                label: CampaignCopy.startsLabel,
                value: formatDayDate(offer.schedule.startsAt),
              ),
              const SizedBox(height: SrSpacing.md),
              _Fact(
                label: CampaignCopy.endsLabel,
                value: CampaignCopy.endDateValue(offer.schedule),
              ),
              const SizedBox(height: SrSpacing.md),
              _Fact(
                label: CampaignCopy.timeZoneLabel,
                value: offer.schedule.timeZoneName,
              ),
              const SizedBox(height: SrSpacing.md),
              // States which zone the dates above are in. The app ships no IANA
              // database and cannot render the campaign's own wall clock;
              // disclosing that is better than implying otherwise.
              Text(
                CampaignCopy.timeZoneNote(offer.schedule.timeZoneName),
                style: SrTypography.caption.copyWith(color: sr.textMuted),
              ),
            ],
          ),
        ),

        // -- 9. Stacking -------------------------------------------------------
        const SizedBox(height: SrSpacing.xxl),
        SrSectionCard(
          title: CampaignCopy.stackingSectionTitle,
          child: _IconLine(
            icon: offer.stackingMode.isExclusive
                ? Icons.lock_outline_rounded
                : Icons.layers_outlined,
            text: CampaignCopy.stackingSentence(offer.stackingMode),
          ),
        ),

        // -- 10. The calculation-engine notice ---------------------------------
        const SizedBox(height: SrSpacing.xxl),
        const SrAlert(message: CampaignCopy.engineNotice),
      ],
    );
  }
}

/// A labelled fact in a section card.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: SrTypography.caption.copyWith(color: sr.textMuted)),
        const SizedBox(height: SrSpacing.xxs),
        Text(value, style: SrTypography.body.copyWith(color: sr.foreground)),
      ],
    );
  }
}

/// A sentence with a leading icon.
///
/// The icon repeats what the sentence already says — team versus individual,
/// exclusive versus stackable — so it is a second channel rather than the only
/// one, and it carries no semantics of its own.
class _IconLine extends StatelessWidget {
  const _IconLine({required this.icon, required this.text});

  final IconData icon;
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
            child: Icon(icon, size: 18, color: sr.textMuted),
          ),
        ),
        const SizedBox(width: SrSpacing.md),
        Expanded(
          child: Text(
            text,
            style: SrTypography.body.copyWith(color: sr.textBody),
          ),
        ),
      ],
    );
  }
}

/// One eligible product.
///
/// Not tappable and carrying no controls, for the same reason as
/// `RetailerProductCard`: a Retailer cannot change a product assignment, and
/// this client deliberately does not carry `product_id`, so there is nothing to
/// address. Absent brand or barcode is omitted rather than dashed.
class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product});

  final CampaignProduct product;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    final String detail = <String>[
      product.productCode,
      if (product.brand != null) product.brand!,
      if (product.barcode != null) product.barcode!,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: SrSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: SrSpacing.xs),
            child: ExcludeSemantics(
              child: Icon(
                Icons.inventory_2_outlined,
                size: 15,
                color: sr.textMuted,
              ),
            ),
          ),
          const SizedBox(width: SrSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  product.productName,
                  style: SrTypography.body.copyWith(color: sr.foreground),
                ),
                const SizedBox(height: SrSpacing.xxs),
                Text(
                  detail,
                  style: SrTypography.caption.copyWith(color: sr.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
