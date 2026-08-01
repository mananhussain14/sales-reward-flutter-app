import 'package:supabase_flutter/supabase_flutter.dart';

/// The Retailer Owner campaign list RPC, named exactly once in the application.
const String retailerCampaignsRpc = 'list_my_retailer_campaigns';

/// The Retailer Owner campaign detail RPC, named exactly once.
const String retailerCampaignDetailRpc = 'get_my_retailer_campaign';

/// The Retailer Owner campaign product RPC, named exactly once.
const String retailerCampaignProductsRpc = 'list_my_retailer_campaign_products';

/// The parameter name `get_my_retailer_campaign` and
/// `list_my_retailer_campaign_products` both declare.
const String campaignIdParam = 'p_campaign_id';

/// Invokes `list_my_retailer_campaigns()`.
///
/// ## Zero arguments, and that is the whole contract
///
/// The typedef takes nothing, because the function takes nothing. There is no
/// Retailer organization id, campaign id, version id, Vendor id, group id, auth
/// user id, profile id, membership id, tenant id, role code, permission code,
/// lifecycle filter, search term, sort or page selector to express at this
/// boundary.
///
/// The absence of a **Vendor** parameter matters as much as the absence of a
/// Retailer one: campaigns are the join between a Vendor's offer and a
/// Retailer's assignment, and a client that could name a Vendor could ask what
/// that Vendor offers somebody else. There is no such parameter and no such
/// overload.
typedef RetailerCampaignsInvoker = Future<Object?> Function();

/// Invokes a campaign-addressed Retailer Owner RPC.
///
/// One argument, and it is an **address**. Both functions re-derive the
/// Retailer from `auth.uid()` through
/// `resolve_retailer_member_organization('CAMPAIGNS_VIEW_ASSIGNED')` and match
/// the id against *that* Retailer's assignments, so the value cannot widen what
/// the caller may see — it can only select from within it, or select nothing.
typedef RetailerCampaignByIdInvoker =
    Future<Object?> Function(String campaignId);

/// The production list invoker. **No `params` map is passed, not even an empty
/// one.**
RetailerCampaignsInvoker supabaseRetailerCampaignsInvoker(
  SupabaseClient client,
) {
  return () => client.rpc<Object?>(retailerCampaignsRpc);
}

/// The production detail invoker.
RetailerCampaignByIdInvoker supabaseRetailerCampaignDetailInvoker(
  SupabaseClient client,
) {
  return (String campaignId) => client.rpc<Object?>(
    retailerCampaignDetailRpc,
    params: <String, Object?>{campaignIdParam: campaignId},
  );
}

/// The production product invoker.
RetailerCampaignByIdInvoker supabaseRetailerCampaignProductsInvoker(
  SupabaseClient client,
) {
  return (String campaignId) => client.rpc<Object?>(
    retailerCampaignProductsRpc,
    params: <String, Object?>{campaignIdParam: campaignId},
  );
}

/// The three Retailer Owner campaign reads.
///
/// Thin by design: it performs the calls and lets exceptions propagate.
///
/// **No table is ever read here.** There is no query against `campaigns`,
/// `campaign_versions`, `campaign_rules`, `campaign_rule_tiers`,
/// `campaign_eligible_retailers`, `campaign_eligible_products`,
/// `campaign_retailer_groups`, `campaign_retailer_group_members`,
/// `vendor_products` or `organizations` under any spelling. All eleven campaign
/// tables are default-deny with zero RLS policies and no privilege for
/// `authenticated`, so RPC is the only way in **by design** — a direct read
/// would return nothing at all, and a client that attempted one would render an
/// empty campaign list for every Retailer.
///
/// **No write.** `create_vendor_campaign_draft`, `update_vendor_campaign_draft`,
/// `publish_vendor_campaign`, `set_vendor_campaign_lifecycle`,
/// `create_vendor_campaign_version`, `create_vendor_retailer_group`,
/// `update_vendor_retailer_group` and `set_vendor_retailer_group_members` are
/// named nowhere in this application. Every one is gated on `CAMPAIGNS_MANAGE`
/// or `RETAILER_GROUPS_MANAGE`, both Vendor capabilities exercised on the Web.
final class RetailerCampaignRpcDataSource {
  const RetailerCampaignRpcDataSource({
    required RetailerCampaignsInvoker campaigns,
    required RetailerCampaignByIdInvoker detail,
    required RetailerCampaignByIdInvoker products,
  }) : _campaigns = campaigns,
       _detail = detail,
       _products = products;

  /// Builds the data source against a live client.
  factory RetailerCampaignRpcDataSource.forClient(SupabaseClient client) {
    return RetailerCampaignRpcDataSource(
      campaigns: supabaseRetailerCampaignsInvoker(client),
      detail: supabaseRetailerCampaignDetailInvoker(client),
      products: supabaseRetailerCampaignProductsInvoker(client),
    );
  }

  final RetailerCampaignsInvoker _campaigns;
  final RetailerCampaignByIdInvoker _detail;
  final RetailerCampaignByIdInvoker _products;

  /// Every campaign in force against this Retailer, in one round trip.
  Future<Object?> fetchCampaigns() => _campaigns();

  /// One campaign, addressed by id. Zero rows for an id that is not this
  /// Retailer's.
  Future<Object?> fetchCampaign(String campaignId) => _detail(campaignId);

  /// The products that campaign counts for this Retailer.
  Future<Object?> fetchCampaignProducts(String campaignId) =>
      _products(campaignId);
}
