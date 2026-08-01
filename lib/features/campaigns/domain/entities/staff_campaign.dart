import 'package:equatable/equatable.dart';

import 'campaign_offer.dart';

/// One row of `list_my_staff_campaigns()` or `get_my_staff_campaign(uuid)`.
///
/// ## A wrapper that adds nothing, on purpose
///
/// It holds [offer] and no other field, because the staff contract returns the
/// seventeen shared columns and nothing else. Using `CampaignOffer` directly
/// would have compiled and would have been a mistake: the two role reads are
/// separate contracts on separate permissions, and a distinct type is what stops
/// a `RetailerCampaign` — which carries a Vendor name a seller may not see —
/// from being handed to a Sales Staff cubit by an edit that type-checks.
///
/// ## The two withheld columns, and why
///
/// * **No `vendor_name`.** Deliberate, and documented in the migration:
///   *"naming the Vendor to a shop-floor seller leaks the supply relationship."*
///   There is no field for it here, so a staff screen cannot render one, and the
///   staff RPC does not return one to be rendered.
///
///   This is a **recorded deviation** from the milestone brief, which asked for
///   a Vendor on the Sales Staff surface. The instruction to use the RPCs
///   exactly as implemented governs: the column is not in
///   `list_my_staff_campaigns()`'s `returns table` clause, and the only ways to
///   obtain it would be to call the Owner read — which refuses a seller with
///   `42501` — or to change the backend, which this milestone must not do.
///
/// * **No `campaign_status`.** The staff contract returns only the derived
///   state, which is the fact that matters to someone selling.
///
/// ## Only two lifecycle states can arrive
///
/// Both staff reads filter `campaign_derived_state(...) in ('ACTIVE',
/// 'SCHEDULED')` in SQL, so a paused, ended or cancelled campaign is simply
/// absent — *"A paused, ended or cancelled campaign offers them nothing and
/// showing it would invite the belief that it does."*
///
/// The client applies **no equivalent filter**. Restating the rule here would
/// create a second definition of what a seller may see, and the client's copy
/// would be the one nobody noticed was wrong.
final class StaffCampaign extends Equatable {
  const StaffCampaign({required this.offer});

  /// Everything both roles read. One parse, one set of wording rules.
  final CampaignOffer offer;

  @override
  List<Object?> get props => <Object?>[offer];
}
