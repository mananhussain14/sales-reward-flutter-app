import 'package:supabase_flutter/supabase_flutter.dart';

import 'retailer_campaign_rpc_data_source.dart' show campaignIdParam;

/// The Sales Staff campaign list RPC, named exactly once in the application.
const String staffCampaignsRpc = 'list_my_staff_campaigns';

/// The Sales Staff campaign detail RPC, named exactly once.
const String staffCampaignDetailRpc = 'get_my_staff_campaign';

/// The Sales Staff campaign product RPC, named exactly once.
const String staffCampaignProductsRpc = 'list_my_staff_campaign_products';

/// Invokes `list_my_staff_campaigns()`.
///
/// ## Zero arguments
///
/// The typedef takes nothing, because the function takes nothing. In particular
/// there is no **profile**, **membership** or **shop** parameter: a seller
/// cannot name another seller, and the contract has no notion of "whose"
/// campaigns to return beyond the caller's own Retailer, which it derives from
/// `auth.uid()` through
/// `resolve_retailer_member_organization('STAFF_CAMPAIGNS_VIEW')`.
///
/// There is no lifecycle filter either. The `ACTIVE`/`SCHEDULED` restriction is
/// applied in SQL and is not a parameter a client could widen.
typedef StaffCampaignsInvoker = Future<Object?> Function();

/// Invokes a campaign-addressed Sales Staff RPC.
///
/// One argument, and it is an **address**. Both functions re-derive the Retailer
/// from `auth.uid()`, match the id against that Retailer's assignments, **and**
/// re-apply the `ACTIVE`/`SCHEDULED` filter — so a seller cannot reach a paused
/// or ended campaign by addressing it directly.
typedef StaffCampaignByIdInvoker = Future<Object?> Function(String campaignId);

/// The production list invoker. **No `params` map is passed, not even an empty
/// one.**
StaffCampaignsInvoker supabaseStaffCampaignsInvoker(SupabaseClient client) {
  return () => client.rpc<Object?>(staffCampaignsRpc);
}

/// The production detail invoker.
StaffCampaignByIdInvoker supabaseStaffCampaignDetailInvoker(
  SupabaseClient client,
) {
  return (String campaignId) => client.rpc<Object?>(
    staffCampaignDetailRpc,
    params: <String, Object?>{campaignIdParam: campaignId},
  );
}

/// The production product invoker.
StaffCampaignByIdInvoker supabaseStaffCampaignProductsInvoker(
  SupabaseClient client,
) {
  return (String campaignId) => client.rpc<Object?>(
    staffCampaignProductsRpc,
    params: <String, Object?>{campaignIdParam: campaignId},
  );
}

/// The three Sales Staff campaign reads.
///
/// A **separate** data source from the Retailer Owner's, naming three different
/// functions on a different permission. The two share only the parameter name,
/// imported rather than retyped so a rename cannot leave one of them behind.
///
/// Nothing here names an Owner RPC. `list_my_retailer_campaigns`,
/// `get_my_retailer_campaign` and `list_my_retailer_campaign_products` do not
/// appear in this file, so a Sales Staff repository cannot reach the Owner
/// contract even by an edit that type-checks — and would be refused with `42501`
/// if it did, because `CAMPAIGNS_VIEW_ASSIGNED` is mapped to `RETAILER_OWNER`
/// alone.
///
/// **No table is ever read here**, and **no write exists**: see
/// [RetailerCampaignRpcDataSource] for the full list of what is absent and why.
final class StaffCampaignRpcDataSource {
  const StaffCampaignRpcDataSource({
    required StaffCampaignsInvoker campaigns,
    required StaffCampaignByIdInvoker detail,
    required StaffCampaignByIdInvoker products,
  }) : _campaigns = campaigns,
       _detail = detail,
       _products = products;

  /// Builds the data source against a live client.
  factory StaffCampaignRpcDataSource.forClient(SupabaseClient client) {
    return StaffCampaignRpcDataSource(
      campaigns: supabaseStaffCampaignsInvoker(client),
      detail: supabaseStaffCampaignDetailInvoker(client),
      products: supabaseStaffCampaignProductsInvoker(client),
    );
  }

  final StaffCampaignsInvoker _campaigns;
  final StaffCampaignByIdInvoker _detail;
  final StaffCampaignByIdInvoker _products;

  /// The campaigns running now or starting soon for this seller's Retailer.
  Future<Object?> fetchCampaigns() => _campaigns();

  /// One campaign, addressed by id.
  Future<Object?> fetchCampaign(String campaignId) => _detail(campaignId);

  /// The products that campaign counts for this seller's Retailer.
  Future<Object?> fetchCampaignProducts(String campaignId) =>
      _products(campaignId);
}
