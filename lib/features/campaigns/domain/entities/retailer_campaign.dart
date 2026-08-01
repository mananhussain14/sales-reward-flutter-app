import 'package:equatable/equatable.dart';

import 'campaign_lifecycle_state.dart';
import 'campaign_offer.dart';

/// One row of `list_my_retailer_campaigns()` or `get_my_retailer_campaign(uuid)`.
///
/// The seventeen shared columns live on [offer]; this type adds the two the
/// **Retailer Owner** contract returns and the Sales Staff contract does not.
///
/// ## What the Owner sees that a seller does not
///
/// * [vendorName] — the organisation running the campaign. The Owner read is
///   gated on `CAMPAIGNS_VIEW_ASSIGNED` and *"returns the Vendor's name, which
///   the requirement names explicitly"*.
/// * [managementStatus] — the stored `campaigns.status`. Parsed, never rendered;
///   see [CampaignManagementStatus].
/// * **The whole history.** The Owner read applies no lifecycle filter at all,
///   *"because managing a Retailer means knowing what ran"* — so scheduled,
///   running, paused, ended and cancelled campaigns all arrive. A seller's
///   contract returns only `ACTIVE` and `SCHEDULED`.
///
/// ## What it still does not see
///
/// Nothing about any other Retailer, no Retailer group name, no Vendor-wide
/// audience count, no exclusivity key, no priority, no version id, no snapshot
/// id and no organization id. None of those is in either contract's `returns
/// table` clause, so there is no field here to hold one and no screen that could
/// render one.
final class RetailerCampaign extends Equatable {
  const RetailerCampaign({
    required this.offer,
    required this.vendorName,
    required this.managementStatus,
  });

  /// Everything both roles read. One parse, one set of wording rules.
  final CampaignOffer offer;

  /// `organizations.name` for the campaign's Vendor. `NOT NULL`.
  final String vendorName;

  /// `campaigns.status`, the management status a human wrote.
  ///
  /// Validated at the boundary and **not displayed**. [CampaignOffer.lifecycleState]
  /// is the fact a reader needs; it already folds this column together with the
  /// period, and showing both would put "Published" beside "Finished" on one
  /// card and leave the reader to work out which governs.
  final CampaignManagementStatus managementStatus;

  @override
  List<Object?> get props => <Object?>[offer, vendorName, managementStatus];
}
