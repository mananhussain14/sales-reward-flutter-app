import 'package:equatable/equatable.dart';

import '../../domain/entities/campaign_lifecycle_state.dart';
import '../../domain/entities/campaign_offer.dart';
import '../../domain/entities/retailer_campaign.dart';
import '../../domain/entities/staff_campaign.dart';

/// Who is reading.
///
/// Presentation only. It selects a **voice** — an Owner is told what happens to
/// their staff, a seller is told what happens to them — and it decides whether a
/// Vendor name has a place on the screen. It is never consulted to decide
/// whether something may be read: the backend decided that on every call, twice
/// over, through two different permissions.
enum CampaignAudience {
  /// Reading `list_my_retailer_campaigns()` / `get_my_retailer_campaign()`,
  /// under `CAMPAIGNS_VIEW_ASSIGNED`.
  retailerOwner,

  /// Reading `list_my_staff_campaigns()` / `get_my_staff_campaign()`, under
  /// `STAFF_CAMPAIGNS_VIEW`.
  salesStaff,
}

/// One campaign, as a screen needs it — whichever role is looking.
///
/// ## Why the two roles converge here and not earlier
///
/// [RetailerCampaign] and [StaffCampaign] are separate types on purpose: they
/// come from separate contracts on separate permissions, and keeping them apart
/// is what stops an Owner's row — which carries a Vendor name a seller may not
/// see — from being handed to a Sales Staff cubit by an edit that type-checks.
///
/// But *rendering* them is one job. The lifecycle grouping, the reward sentence,
/// the eligibility sentence, the zero-product rule and the card layout are
/// identical facts about an identical seventeen-column offer, and writing them
/// twice would guarantee that one copy eventually described a campaign
/// differently from the other.
///
/// So the conversion happens exactly here, at the boundary between the two
/// typed reads and the one set of widgets, through two named constructors that
/// cannot be mixed up.
///
/// ## [vendorName] is null for a seller, structurally
///
/// [CampaignPresentation.staff] takes no Vendor name and has nowhere to put one,
/// because `list_my_staff_campaigns()` does not return one — *"naming the Vendor
/// to a shop-floor seller leaks the supply relationship."* Every widget treats
/// null as "omit the line", never as "unknown Vendor", so a seller's card has no
/// empty Vendor row where an Owner's has a name.
final class CampaignPresentation extends Equatable {
  const CampaignPresentation._({
    required this.offer,
    required this.vendorName,
    required this.audience,
  });

  /// From a Retailer Owner row. Carries the Vendor name the Owner contract
  /// returns.
  ///
  /// [RetailerCampaign.managementStatus] is deliberately **not** carried
  /// forward: nothing renders it, and leaving it behind here means no widget can
  /// start.
  CampaignPresentation.retailer(RetailerCampaign campaign)
    : this._(
        offer: campaign.offer,
        vendorName: campaign.vendorName,
        audience: CampaignAudience.retailerOwner,
      );

  /// From a Sales Staff row. There is no Vendor name parameter to pass.
  CampaignPresentation.staff(StaffCampaign campaign)
    : this._(
        offer: campaign.offer,
        vendorName: null,
        audience: CampaignAudience.salesStaff,
      );

  /// The seventeen shared columns.
  final CampaignOffer offer;

  /// The Vendor running the campaign, or null when the contract withholds it.
  final String? vendorName;

  final CampaignAudience audience;

  @override
  List<Object?> get props => <Object?>[offer, vendorName, audience];
}

/// A heading a campaign list is grouped under.
///
/// Ordered by what a reader needs first: what is earning now, then what is
/// about to, then what has stopped.
enum CampaignSectionKind {
  /// `ACTIVE`. Eligible sales count right now.
  runningNow,

  /// `SCHEDULED`. Published, period not started.
  startingSoon,

  /// `PAUSED`. Retailer Owner only — a seller's contract filters it out.
  paused,

  /// `ENDED`. Retailer Owner only.
  finished,

  /// `CANCELLED`. Retailer Owner only.
  cancelled,

  /// `DRAFT`. **Structurally unreachable through either contract** — see
  /// [CampaignLifecycleState]. It exists so the grouping switch is exhaustive
  /// and a state can never be silently dropped from a list; because empty
  /// sections are not rendered, it costs nothing.
  notPublished,
}

/// One rendered group: a heading and the campaigns under it.
final class CampaignSection extends Equatable {
  const CampaignSection({required this.kind, required this.campaigns});

  final CampaignSectionKind kind;
  final List<CampaignPresentation> campaigns;

  @override
  List<Object?> get props => <Object?>[kind, campaigns];
}

/// Groups campaigns into the sections a list renders.
///
/// ## One implementation, both roles
///
/// A Retailer Owner receives five of the six kinds and a seller receives two, so
/// the roles look different on screen — but the *rule* is one function, applied
/// to whatever each contract returned. Neither role filters: what a seller may
/// see is decided by `campaign_derived_state(...) in ('ACTIVE', 'SCHEDULED')` in
/// SQL, and restating that here would put a second definition of it on the
/// device.
///
/// ## Empty sections are not returned
///
/// A heading with nothing under it tells a reader a category exists that they
/// have none of, which on this screen reads as "something is missing". Only
/// sections with at least one campaign come back.
///
/// ## Order within a section is the backend's
///
/// The Owner list arrives `order by cv.starts_at desc, c.name, c.id` — most
/// recently started first, which is what "what ran" wants. The staff list
/// arrives `order by cv.starts_at, c.name, c.id` — soonest first, which is what
/// "what can I sell into" wants. Both are preserved exactly: this function
/// partitions, it does not sort, so the two orderings stay the backend's
/// decision rather than becoming a third one here.
List<CampaignSection> groupCampaignsIntoSections(
  List<CampaignPresentation> campaigns,
) {
  final Map<CampaignSectionKind, List<CampaignPresentation>> grouped =
      <CampaignSectionKind, List<CampaignPresentation>>{};

  for (final CampaignPresentation campaign in campaigns) {
    grouped
        .putIfAbsent(
          sectionKindFor(campaign.offer.lifecycleState),
          () => <CampaignPresentation>[],
        )
        .add(campaign);
  }

  return <CampaignSection>[
    for (final CampaignSectionKind kind in CampaignSectionKind.values)
      if (grouped[kind] != null && grouped[kind]!.isNotEmpty)
        CampaignSection(kind: kind, campaigns: grouped[kind]!),
  ];
}

/// Which section a lifecycle state belongs to.
///
/// Exhaustive over [CampaignLifecycleState], with no default branch — so a state
/// added to the contract later stops this compiling rather than silently
/// vanishing from every list.
CampaignSectionKind sectionKindFor(CampaignLifecycleState state) {
  return switch (state) {
    CampaignLifecycleState.active => CampaignSectionKind.runningNow,
    CampaignLifecycleState.scheduled => CampaignSectionKind.startingSoon,
    CampaignLifecycleState.paused => CampaignSectionKind.paused,
    CampaignLifecycleState.ended => CampaignSectionKind.finished,
    CampaignLifecycleState.cancelled => CampaignSectionKind.cancelled,
    CampaignLifecycleState.draft => CampaignSectionKind.notPublished,
  };
}
