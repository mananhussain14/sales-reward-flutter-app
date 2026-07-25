import 'package:supabase_flutter/supabase_flutter.dart';

/// The three Vendor Product RPCs, named exactly once each.
///
/// The first is **not new**. `list_vendor_products()` shipped with the web
/// catalogue and the mobile milestone reuses it verbatim rather than adding a
/// second list read, which would be a second definition of "this Vendor's
/// products", free to drift from the one the web already renders.
const String listVendorProductsRpc = 'list_vendor_products';
const String getVendorProductDetailRpc = 'get_vendor_product_detail';
const String listVendorProductAssignedRetailersRpc =
    'list_vendor_product_assigned_retailers';

/// The **only** parameter any of them accepts.
const String productIdParameter = 'p_product_id';

/// Invokes `list_vendor_products()` and returns its raw body.
///
/// ## The signature is the security property
///
/// The RPC takes no arguments at all, and this typedef takes none either. That
/// is not a convenience — it makes an auth user id, profile id, Vendor
/// organization id, tenant id, Retailer organization id, product id, product
/// code, product status, assignment status, role code, permission code, search
/// term or page cursor **impossible to express** at this boundary. There is no
/// argument to pass, so there is no argument to get wrong, and no future edit can
/// quietly add one without changing this type.
typedef VendorProductListInvoker = Future<Object?> Function();

/// Invokes `get_vendor_product_detail(uuid)`.
///
/// One `String`, and it is a `vendor_products.id`. No identity travels beside
/// it: the function derives the Vendor from `auth.uid()` via
/// `get_vendor_super_admin_context()` and uses the id only to select which
/// already-authorized row is read.
///
/// Holding a product id therefore grants nothing. The row is matched on **both**
/// its own id and the derived Vendor, and `vendor_organization_id` is `NOT NULL`
/// and immutable by trigger — so another Vendor's product id, an id that names
/// nothing, and an id from another table are all equally inert and all answer
/// zero rows.
typedef VendorProductDetailInvoker = Future<Object?> Function(String productId);

/// Invokes `list_vendor_product_assigned_retailers(uuid)`.
///
/// The same selector as the detail read, deliberately: two operations addressed
/// by one id cannot drift into two address spaces, and it is what makes the
/// detail read genuinely authoritative about the id this one was asked for.
///
/// The **product** id and never a Retailer organization id. A product id names
/// one Vendor's own row; a Retailer organization id names a tenant other Vendors
/// may also manage, which is why the backend returns it and never accepts it.
typedef VendorProductAssignedRetailersInvoker =
    Future<Object?> Function(String productId);

/// The production invokers.
///
/// The only place in the application that names a Vendor Product RPC and touches
/// the Supabase client for it. Note the call sites: a function name, and — twice
/// — a single product id.
VendorProductListInvoker supabaseVendorProductsInvoker(SupabaseClient client) {
  return () => client.rpc<Object?>(listVendorProductsRpc);
}

VendorProductDetailInvoker supabaseVendorProductDetailInvoker(
  SupabaseClient client,
) {
  return (String productId) => client.rpc<Object?>(
    getVendorProductDetailRpc,
    params: <String, Object?>{productIdParameter: productId},
  );
}

VendorProductAssignedRetailersInvoker
supabaseVendorProductAssignedRetailersInvoker(SupabaseClient client) {
  return (String productId) => client.rpc<Object?>(
    listVendorProductAssignedRetailersRpc,
    params: <String, Object?>{productIdParameter: productId},
  );
}

/// Reads the Vendor Product data a Vendor Super Admin is entitled to.
///
/// Thin by design: it performs each call and lets exceptions propagate. Turning
/// an exception into a `Failure` is the repository's job and turning a body into
/// domain objects is the parser's, so each of the three has one reason to
/// change.
///
/// **No table is ever read here.** There is no query against `vendor_products`,
/// `vendor_product_retailer_assignments`, `vendor_retailers` or `organizations`,
/// and none against `auth.users` under any spelling. Both product tables have
/// RLS enabled with **zero policies** and no privilege for `anon` or
/// `authenticated` — RPC is the only way in, by design — so a direct read here
/// would not merely be poor layering, it would not work.
///
/// **No storage call, and no image request of any kind.** There is no product
/// image column, no product bucket and no signed-URL path anywhere in the
/// product, so there is nothing here to fetch and nothing to sign.
///
/// **No write.** Product creation, editing, status changes, assignment and
/// withdrawal all exist as shipped RPCs and none of them is named in this file.
final class VendorProductRpcDataSource {
  const VendorProductRpcDataSource({
    required VendorProductListInvoker products,
    required VendorProductDetailInvoker detail,
    required VendorProductAssignedRetailersInvoker assignedRetailers,
  }) : _products = products,
       _detail = detail,
       _assignedRetailers = assignedRetailers;

  /// Builds the data source against a live client.
  factory VendorProductRpcDataSource.forClient(SupabaseClient client) {
    return VendorProductRpcDataSource(
      products: supabaseVendorProductsInvoker(client),
      detail: supabaseVendorProductDetailInvoker(client),
      assignedRetailers: supabaseVendorProductAssignedRetailersInvoker(client),
    );
  }

  final VendorProductListInvoker _products;
  final VendorProductDetailInvoker _detail;
  final VendorProductAssignedRetailersInvoker _assignedRetailers;

  Future<Object?> fetchProducts() => _products();

  Future<Object?> fetchDetail(String productId) => _detail(productId);

  Future<Object?> fetchAssignedRetailers(String productId) =>
      _assignedRetailers(productId);
}
