import 'package:supabase_flutter/supabase_flutter.dart';

/// The one Retailer assigned-product RPC, named exactly once in the application.
const String retailerAssignedProductsRpc = 'list_retailer_assigned_products';

/// Invokes `list_retailer_assigned_products()`.
///
/// ## Zero arguments, and that is the whole contract
///
/// The typedef takes nothing, because the function takes nothing. There is no
/// Retailer organization id, product id, vendor id, assignment id, auth user id,
/// profile id, membership id, tenant id, role code, permission code, status
/// filter, search term, sort or page selector to express at this boundary.
///
/// The absence of a **vendor** parameter matters as much as the absence of a
/// retailer one: the assignment rows are the join between the two, and a client
/// that could name a Vendor could ask which of its products some other Retailer
/// holds. There is no such parameter and no such overload.
typedef RetailerAssignedProductsInvoker = Future<Object?> Function();

/// The production invoker.
///
/// The only place in the application that names this RPC and touches the
/// Supabase client for it.
///
/// **No `params` map is passed, not even an empty one.**
RetailerAssignedProductsInvoker supabaseRetailerAssignedProductsInvoker(
  SupabaseClient client,
) {
  return () => client.rpc<Object?>(retailerAssignedProductsRpc);
}

/// Reads the products currently assigned to the caller's Retailer.
///
/// Thin by design: it performs the call and lets exceptions propagate.
///
/// **No table is ever read here.** There is no query against
/// `vendor_product_retailer_assignments`, `vendor_products`, `organizations` or
/// `organization_members` under any spelling. Both product tables are
/// default-deny with zero RLS policies and no privilege for `authenticated`, so
/// RPC is the only way in **by design** — a direct read would return nothing at
/// all, and a client that attempted one would render an empty catalogue for
/// every Retailer.
///
/// **No write.** Neither `assign_vendor_product_to_retailer` nor
/// `unassign_vendor_product_from_retailer` is named here or anywhere else in the
/// Retailer portal — both are Vendor operations on `PRODUCT_RETAILER_ASSIGN`.
/// Product create, edit and status are likewise Vendor RPCs and appear nowhere
/// in this feature.
final class RetailerProductRpcDataSource {
  const RetailerProductRpcDataSource({
    required RetailerAssignedProductsInvoker products,
  }) : _products = products;

  /// Builds the data source against a live client.
  factory RetailerProductRpcDataSource.forClient(SupabaseClient client) {
    return RetailerProductRpcDataSource(
      products: supabaseRetailerAssignedProductsInvoker(client),
    );
  }

  final RetailerAssignedProductsInvoker _products;

  /// Every currently assigned product, in one round trip.
  Future<Object?> fetchProducts() => _products();
}
