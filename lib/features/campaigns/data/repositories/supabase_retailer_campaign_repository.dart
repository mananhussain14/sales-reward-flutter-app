import '../../../../core/errors/retailer_read_problem.dart';
import '../../../../core/parsing/rpc_row.dart';
import '../../domain/entities/retailer_campaign.dart';
import '../../domain/repositories/retailer_campaign_repository.dart';
import '../datasources/retailer_campaign_rpc_data_source.dart';
import '../models/campaign_parsers.dart';

/// The real [RetailerCampaignRepository].
///
/// Call, parse, classify. Each is somebody else's code, so this class contains
/// no branching of its own beyond "did it throw?" and "did it return a row?".
///
/// ## It reproduces no backend authorization logic
///
/// There is no Retailer organization id here, no Vendor id, no membership
/// lookup, no role check and no permission check. Whether this caller may read
/// assigned campaigns is decided in SQL by
/// `resolve_retailer_member_organization('CAMPAIGNS_VIEW_ASSIGNED')`, which
/// `RETAILER_OWNER` satisfies and every other role does not.
///
/// ## It reproduces no lifecycle logic either
///
/// The `c.published_version_id = cv.id` join — which keeps a superseded
/// version's snapshot out of the answer — is the backend's, and is not restated
/// here. Neither is `campaign_derived_state`: no comparison against the device
/// clock happens anywhere in this feature, so a phone with a wrong clock cannot
/// move a campaign between sections.
///
/// **A denial is never an empty list.** `42501` becomes
/// [RetailerReadProblem.denied]; "you may not read this" and "no Vendor targets
/// you" are opposite claims.
final class SupabaseRetailerCampaignRepository
    implements RetailerCampaignRepository {
  const SupabaseRetailerCampaignRepository({
    required RetailerCampaignRpcDataSource rpc,
    Duration timeout = retailerReadTimeout,
  }) : _rpc = rpc,
       _timeout = timeout;

  final RetailerCampaignRpcDataSource _rpc;
  final Duration _timeout;

  @override
  Future<RetailerCampaignsResult> campaigns() async {
    final Object? raw;
    try {
      raw = await _rpc.fetchCampaigns().timeout(_timeout);
    } on Object catch (error) {
      return RetailerCampaignsFailed(classifyRetailerReadError(error));
    }

    try {
      return RetailerCampaignsLoaded(
        CampaignParsers.parseRetailerCampaigns(raw),
      );
    } on RpcFormatException {
      // The exception's own `reason` is developer-facing and stays here. Only
      // the discriminant travels onward.
      return const RetailerCampaignsFailed(RetailerReadProblem.malformed);
    }
  }

  @override
  Future<RetailerCampaignDetailResult> campaignDetail(String campaignId) async {
    // Refused on the device, before the value is put into a `uuid` parameter.
    //
    // This is NOT authorization, and it does not narrow what the backend
    // decides: a well-formed id belonging to another Retailer reaches exactly
    // this same answer, because `get_my_retailer_campaign()` returns zero rows
    // for it. What the guard buys is that a mistyped deep link produces the
    // feature's own safe not-found rather than a PostgREST cast error carrying
    // a Postgres message.
    if (!isCampaignIdShaped(campaignId)) {
      return const RetailerCampaignDetailMissing();
    }

    final Object? rawCampaign;
    try {
      rawCampaign = await _rpc.fetchCampaign(campaignId).timeout(_timeout);
    } on Object catch (error) {
      return RetailerCampaignDetailFailed(classifyRetailerReadError(error));
    }

    final RetailerCampaign? campaign;
    try {
      campaign = CampaignParsers.parseRetailerCampaignSingle(rawCampaign);
    } on RpcFormatException {
      return const RetailerCampaignDetailFailed(RetailerReadProblem.malformed);
    }

    if (campaign == null) {
      // Zero rows. Unknown id, another Retailer's id, and a campaign whose
      // version is no longer in force are one answer — see
      // [RetailerCampaignDetailMissing] for why they must stay one.
      //
      // The product read is skipped: it resolves through the same assignment
      // join and would return an empty list, so a second request would cost a
      // round trip and buy nothing.
      return const RetailerCampaignDetailMissing();
    }

    final Object? rawProducts;
    try {
      rawProducts = await _rpc
          .fetchCampaignProducts(campaignId)
          .timeout(_timeout);
    } on Object catch (error) {
      // The campaign was readable and its products were not. Reported as a
      // failure rather than as a campaign with an empty product list: an empty
      // list is the zero-eligible-product state, which this screen warns about
      // prominently, and fabricating it here would put that warning on a
      // campaign whose products simply could not be read.
      return RetailerCampaignDetailFailed(classifyRetailerReadError(error));
    }

    try {
      return RetailerCampaignDetailLoaded(
        campaign: campaign,
        products: CampaignParsers.parseCampaignProducts(rawProducts),
      );
    } on RpcFormatException {
      return const RetailerCampaignDetailFailed(RetailerReadProblem.malformed);
    }
  }
}
