import '../../../../core/errors/retailer_read_problem.dart';
import '../../../../core/parsing/rpc_row.dart';
import '../../domain/entities/staff_campaign.dart';
import '../../domain/repositories/staff_campaign_repository.dart';
import '../datasources/staff_campaign_rpc_data_source.dart';
import '../models/campaign_parsers.dart';

/// The real [StaffCampaignRepository].
///
/// Structurally the twin of [SupabaseRetailerCampaignRepository] — call, parse,
/// classify — over three **different** RPCs on a **different** permission.
///
/// ## It applies no lifecycle filter of its own
///
/// The `ACTIVE`/`SCHEDULED` restriction that keeps a paused, ended or cancelled
/// campaign off a seller's screen is applied in SQL, on the derived state, by
/// all three staff functions. Restating it here would create a second definition
/// of what a seller may see, and the client's copy would be the one nobody
/// noticed had drifted.
///
/// The consequence is worth naming: a campaign that is paused **while a seller
/// is looking at it** disappears on the next read, and its detail address starts
/// answering [StaffCampaignDetailMissing]. That is the contract working, not a
/// bug — and it is why the not-found screen says nothing about why.
///
/// ## It reproduces no authorization logic
///
/// No Retailer id, no profile id, no shop, no role, no permission check. The
/// backend resolves the caller through
/// `resolve_retailer_member_organization('STAFF_CAMPAIGNS_VIEW')` on every one
/// of the three calls.
final class SupabaseStaffCampaignRepository implements StaffCampaignRepository {
  const SupabaseStaffCampaignRepository({
    required StaffCampaignRpcDataSource rpc,
    Duration timeout = retailerReadTimeout,
  }) : _rpc = rpc,
       _timeout = timeout;

  final StaffCampaignRpcDataSource _rpc;
  final Duration _timeout;

  @override
  Future<StaffCampaignsResult> campaigns() async {
    final Object? raw;
    try {
      raw = await _rpc.fetchCampaigns().timeout(_timeout);
    } on Object catch (error) {
      return StaffCampaignsFailed(classifyRetailerReadError(error));
    }

    try {
      return StaffCampaignsLoaded(CampaignParsers.parseStaffCampaigns(raw));
    } on RpcFormatException {
      return const StaffCampaignsFailed(RetailerReadProblem.malformed);
    }
  }

  @override
  Future<StaffCampaignDetailResult> campaignDetail(String campaignId) async {
    // Refused on the device, before the value is put into a `uuid` parameter.
    // Not authorization: see the equivalent guard in the Retailer repository.
    if (!isCampaignIdShaped(campaignId)) {
      return const StaffCampaignDetailMissing();
    }

    final Object? rawCampaign;
    try {
      rawCampaign = await _rpc.fetchCampaign(campaignId).timeout(_timeout);
    } on Object catch (error) {
      return StaffCampaignDetailFailed(classifyRetailerReadError(error));
    }

    final StaffCampaign? campaign;
    try {
      campaign = CampaignParsers.parseStaffCampaignSingle(rawCampaign);
    } on RpcFormatException {
      return const StaffCampaignDetailFailed(RetailerReadProblem.malformed);
    }

    if (campaign == null) {
      // Zero rows. Unknown id, another Retailer's campaign, and a campaign that
      // is no longer ACTIVE or SCHEDULED are one answer, and must stay one — a
      // seller must not be able to learn that a campaign exists but has been
      // paused.
      return const StaffCampaignDetailMissing();
    }

    final Object? rawProducts;
    try {
      rawProducts = await _rpc
          .fetchCampaignProducts(campaignId)
          .timeout(_timeout);
    } on Object catch (error) {
      // Never degraded to an empty product list: an empty list is the
      // zero-eligible-product state this screen warns about prominently, and it
      // must be the backend's answer rather than this method's.
      return StaffCampaignDetailFailed(classifyRetailerReadError(error));
    }

    try {
      return StaffCampaignDetailLoaded(
        campaign: campaign,
        products: CampaignParsers.parseCampaignProducts(rawProducts),
      );
    } on RpcFormatException {
      return const StaffCampaignDetailFailed(RetailerReadProblem.malformed);
    }
  }
}
