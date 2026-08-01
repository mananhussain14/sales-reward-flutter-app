import '../../../../core/errors/retailer_read_problem.dart';
import '../entities/campaign_product.dart';
import '../entities/retailer_campaign.dart';

/// The outcome of the Retailer Owner campaign **list** read.
sealed class RetailerCampaignsResult {
  const RetailerCampaignsResult();
}

/// The rows, already parsed. Possibly empty, which is a real answer meaning "no
/// Vendor currently targets a campaign at your Retailer".
final class RetailerCampaignsLoaded extends RetailerCampaignsResult {
  const RetailerCampaignsLoaded(this.campaigns);

  final List<RetailerCampaign> campaigns;
}

/// The read did not produce an answer. Never an empty list.
final class RetailerCampaignsFailed extends RetailerCampaignsResult {
  const RetailerCampaignsFailed(this.problem);

  final RetailerReadProblem problem;
}

/// The outcome of the Retailer Owner campaign **detail** read.
sealed class RetailerCampaignDetailResult {
  const RetailerCampaignDetailResult();
}

/// The campaign, and the products it counts for this Retailer.
///
/// [products] may be empty while the campaign exists — that is the
/// zero-eligible-product case, and it is a truthful answer rather than a
/// failure.
final class RetailerCampaignDetailLoaded extends RetailerCampaignDetailResult {
  const RetailerCampaignDetailLoaded({
    required this.campaign,
    required this.products,
  });

  final RetailerCampaign campaign;
  final List<CampaignProduct> products;
}

/// There is no campaign at this address for this caller.
///
/// **One member for four different situations**, and that is the security
/// property rather than an omission:
///
/// * no campaign has that id;
/// * a campaign has it, but no version of it targets this Retailer;
/// * a campaign has it and targeted this Retailer under a version that is no
///   longer in force;
/// * the id is not a UUID at all, and was refused on the device before any
///   request was made.
///
/// `get_my_retailer_campaign()` answers the first three with **zero rows** —
/// *"A campaign id that is not assigned to this Retailer returns ZERO ROWS,
/// exactly as an unknown id does."* The fourth is answered identically here so
/// that a malformed id cannot be told from a well-formed one either.
///
/// Distinguishing them in the UI would rebuild the existence oracle the SQL is
/// careful to deny: a Retailer Owner could otherwise page through ids and learn
/// which of them name real campaigns at other Retailers.
///
/// It is also **not** a failure and offers **no retry**. The backend answered;
/// asking again produces the same answer.
final class RetailerCampaignDetailMissing extends RetailerCampaignDetailResult {
  const RetailerCampaignDetailMissing();
}

/// The read did not produce an answer. Distinct from
/// [RetailerCampaignDetailMissing] on purpose: "we could not reach the service"
/// and "there is nothing here for you" are opposite claims, and only one is
/// worth retrying.
final class RetailerCampaignDetailFailed extends RetailerCampaignDetailResult {
  const RetailerCampaignDetailFailed(this.problem);

  final RetailerReadProblem problem;
}

/// The Retailer Owner's read-only view of the campaigns assigned to their
/// Retailer.
///
/// ## The signature is the security property
///
/// [campaigns] takes **no arguments at all**. There is no Retailer organization
/// id, no Vendor id, no group id, no version id, no profile id, no auth user id,
/// no role code, no permission code, no status filter, no search term, no sort
/// and no page selector anywhere on this interface.
///
/// `public.list_my_retailer_campaigns()` is declared with an empty parameter
/// list and derives its scope from
/// `resolve_retailer_member_organization('CAMPAIGNS_VIEW_ASSIGNED')`, which
/// resolves the caller from `auth.uid()`. There is nothing for a client to
/// supply and therefore nothing for a client to forge.
///
/// [campaignDetail] and its product list take exactly one argument, and it is an
/// **address, not an authorization claim**. Both RPCs re-derive the Retailer
/// server-side and match the id against *that* Retailer's assignments; an id
/// belonging to somebody else returns zero rows, which is
/// [RetailerCampaignDetailMissing] — the same answer an unknown id gets.
///
/// ## Read-only, and there is nowhere to add a write
///
/// No create, update, publish, pause, resume, version, cancel or draft method
/// exists here, and none can be added without changing this file. Every one of
/// those is a **Vendor** operation gated on `CAMPAIGNS_MANAGE`, performed on the
/// Web application, and no such RPC is named anywhere in this Flutter
/// application. A Retailer Owner holds `CAMPAIGNS_VIEW_ASSIGNED`, which permits
/// three reads and nothing else.
///
/// ## Retailer Owner alone — not the Retailer Manager
///
/// `CAMPAIGNS_VIEW_ASSIGNED` is mapped to `RETAILER_OWNER` only. A Retailer
/// Manager is refused with `42501`, which is why there is no campaign
/// destination in the Manager's navigation and no Manager route to one.
abstract interface class RetailerCampaignRepository {
  /// `public.list_my_retailer_campaigns()` — every campaign in force against
  /// this Retailer, in one round trip.
  ///
  /// Returns the **whole history**: scheduled, running, paused, ended and
  /// cancelled. The contract applies no lifecycle filter, and this client
  /// applies none either.
  ///
  /// Only versions that are **in force** appear — both reads join
  /// `c.published_version_id = cv.id` — because *"a superseded version's
  /// snapshot is history, and showing it would present an offer that has been
  /// replaced."*
  ///
  /// An empty list means no Vendor currently targets a campaign at this
  /// Retailer. It never means "you are not allowed": a refusal is `42501` and
  /// arrives as [RetailerReadProblem.denied].
  Future<RetailerCampaignsResult> campaigns();

  /// `public.get_my_retailer_campaign(uuid)` followed, only if a row came back,
  /// by `public.list_my_retailer_campaign_products(uuid)`.
  ///
  /// The product read is skipped entirely when the campaign is
  /// [RetailerCampaignDetailMissing]. It would return an empty list anyway — it
  /// resolves through the same assignment join — so skipping it costs no
  /// information and avoids a second request for an address that answered
  /// nothing.
  ///
  /// [campaignId] is an address. See the interface doc.
  Future<RetailerCampaignDetailResult> campaignDetail(String campaignId);
}
