import '../../../../core/errors/retailer_read_problem.dart';
import '../entities/campaign_product.dart';
import '../entities/staff_campaign.dart';

/// The outcome of the Sales Staff campaign **list** read.
sealed class StaffCampaignsResult {
  const StaffCampaignsResult();
}

/// The rows, already parsed. Possibly empty — a real answer meaning "nothing is
/// running or starting soon for your Retailer".
final class StaffCampaignsLoaded extends StaffCampaignsResult {
  const StaffCampaignsLoaded(this.campaigns);

  final List<StaffCampaign> campaigns;
}

/// The read did not produce an answer. Never an empty list.
final class StaffCampaignsFailed extends StaffCampaignsResult {
  const StaffCampaignsFailed(this.problem);

  final RetailerReadProblem problem;
}

/// The outcome of the Sales Staff campaign **detail** read.
sealed class StaffCampaignDetailResult {
  const StaffCampaignDetailResult();
}

/// The campaign, and the products it counts for this seller's Retailer.
final class StaffCampaignDetailLoaded extends StaffCampaignDetailResult {
  const StaffCampaignDetailLoaded({
    required this.campaign,
    required this.products,
  });

  final StaffCampaign campaign;
  final List<CampaignProduct> products;
}

/// There is no campaign at this address for this caller.
///
/// The same single member for every reason, exactly as
/// [RetailerCampaignDetailMissing] — and here it covers one situation more,
/// because the staff contract is narrower:
///
/// * no campaign has that id;
/// * a campaign has it but does not target this seller's Retailer;
/// * it targets this Retailer but its derived state is **not** `ACTIVE` or
///   `SCHEDULED` — a paused, ended or cancelled campaign is out of contract for
///   a seller, and `get_my_staff_campaign()` returns zero rows for it;
/// * the id is not a UUID, and was refused on the device.
///
/// All four produce the identical screen. A seller must not be able to learn
/// that a campaign exists but has been paused, which a distinct "this campaign
/// is paused" state would tell them.
final class StaffCampaignDetailMissing extends StaffCampaignDetailResult {
  const StaffCampaignDetailMissing();
}

/// The read did not produce an answer. Distinct from
/// [StaffCampaignDetailMissing]: only one of the two is worth retrying.
final class StaffCampaignDetailFailed extends StaffCampaignDetailResult {
  const StaffCampaignDetailFailed(this.problem);

  final RetailerReadProblem problem;
}

/// A Sales Staff member's read-only view of the campaigns they can sell into.
///
/// ## A separate interface, not a narrower use of the Owner's
///
/// The backend made the same choice and recorded why: `STAFF_CAMPAIGNS_VIEW` is
/// *"A SEPARATE permission rather than a `SALES_STAFF` mapping to
/// `CAMPAIGNS_VIEW_ASSIGNED` … One permission behind both would make widening
/// either widen the other."* Two interfaces here mirror two permissions there,
/// so a seller's repository cannot be handed an Owner's RPC by an edit that
/// type-checks.
///
/// ## The signature is the security property
///
/// [campaigns] takes **no arguments at all** — no Retailer, no shop, no Vendor,
/// no profile, no auth user id, no role, no permission, no filter.
/// `public.list_my_staff_campaigns()` is declared with an empty parameter list
/// and scopes itself with
/// `resolve_retailer_member_organization('STAFF_CAMPAIGNS_VIEW')`.
///
/// A seller cannot name another seller, and there is no parameter through which
/// they could try: the contract has no notion of "whose" campaigns to return
/// beyond the caller's own Retailer, and nothing on this interface could carry
/// one.
///
/// [campaignDetail] takes an **address**, re-checked server-side against both
/// the caller's Retailer and the `ACTIVE`/`SCHEDULED` filter.
///
/// ## Read-only, and narrower still than the Owner's
///
/// No write of any kind, and no Owner read either: there is no method here for
/// the Retailer's campaign history, and a seller calling
/// `list_my_retailer_campaigns()` would be refused with `42501` regardless,
/// because `CAMPAIGNS_VIEW_ASSIGNED` is mapped to `RETAILER_OWNER` alone.
abstract interface class StaffCampaignRepository {
  /// `public.list_my_staff_campaigns()` — the campaigns running now or starting
  /// soon for this seller's Retailer, in one round trip.
  ///
  /// **`ACTIVE` and `SCHEDULED` only.** The filter is applied in SQL, on the
  /// derived state rather than the stored status, *"so an ended campaign
  /// disappears from a seller's list the moment its end passes without any job
  /// having to sweep it."*
  ///
  /// This client restates none of that. An empty list is a real answer; a
  /// refusal is `42501` and arrives as [RetailerReadProblem.denied].
  Future<StaffCampaignsResult> campaigns();

  /// `public.get_my_staff_campaign(uuid)` followed, only if a row came back, by
  /// `public.list_my_staff_campaign_products(uuid)`.
  ///
  /// The product read carries the same `ACTIVE`/`SCHEDULED` restriction as the
  /// other two staff reads, *"so a seller cannot enumerate the product scope of
  /// a campaign they are not currently selling into."* It is skipped when the
  /// campaign is [StaffCampaignDetailMissing].
  Future<StaffCampaignDetailResult> campaignDetail(String campaignId);
}
