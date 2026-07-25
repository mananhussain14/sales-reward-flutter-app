import 'package:supabase_flutter/supabase_flutter.dart';

/// The three Vendor Retailer RPCs, named exactly once each.
const String listVendorRetailersRpc = 'list_vendor_retailers';
const String getVendorRetailerDetailRpc = 'get_vendor_retailer_detail';
const String listVendorRetailerShopsRpc = 'list_vendor_retailer_shops';

/// The **only** parameter any of them accepts.
const String relationshipIdParameter = 'p_relationship_id';

/// Invokes `list_vendor_retailers()` and returns its raw body.
///
/// ## The signature is the security property
///
/// The RPC takes no arguments at all, and this typedef takes none either. That
/// is not a convenience — it makes a Vendor organization id, user id, profile
/// id, membership id, role code, permission code, tenant id or Retailer
/// organization id **impossible to express** at this boundary. There is no
/// argument to pass, so there is no argument to get wrong, and no future edit
/// can quietly add one without changing this type.
typedef VendorRetailerListInvoker = Future<Object?> Function();

/// Invokes one of the two relationship-addressed reads.
///
/// One `String`, and it is a `vendor_retailers.id`. No identity travels beside
/// it: the function derives the Vendor from `auth.uid()` via
/// `get_vendor_super_admin_context()` and matches the row on **both** its own id
/// and that derived Vendor, neither of which this client can name.
///
/// Holding a relationship id therefore grants nothing. Another Vendor's id is
/// inert — it matches no row and yields the same zero-row answer an unknown id
/// does.
typedef VendorRetailerRelationshipInvoker =
    Future<Object?> Function(String relationshipId);

/// The production invokers.
///
/// The only place in the application that names a Vendor Retailer RPC and
/// touches the Supabase client for it. Note the call sites: a function name,
/// and — twice — a single relationship id.
VendorRetailerListInvoker supabaseVendorRetailersInvoker(
  SupabaseClient client,
) {
  return () => client.rpc<Object?>(listVendorRetailersRpc);
}

VendorRetailerRelationshipInvoker supabaseVendorRetailerDetailInvoker(
  SupabaseClient client,
) {
  return (String relationshipId) => client.rpc<Object?>(
    getVendorRetailerDetailRpc,
    params: <String, Object?>{relationshipIdParameter: relationshipId},
  );
}

VendorRetailerRelationshipInvoker supabaseVendorRetailerShopsInvoker(
  SupabaseClient client,
) {
  return (String relationshipId) => client.rpc<Object?>(
    listVendorRetailerShopsRpc,
    params: <String, Object?>{relationshipIdParameter: relationshipId},
  );
}

/// Reads the Retailer data a Vendor Super Admin is entitled to.
///
/// Thin by design: it performs each call and lets exceptions propagate. Turning
/// an exception into a `Failure` is the repository's job and turning a body into
/// domain objects is the parser's, so each of the three has one reason to
/// change.
///
/// **No table is ever read here.** There is no `.from('vendor_retailers')`, no
/// `.from('organizations')` and no `.from('retailer_shops')`. The join, the
/// counting and the tenant scoping happen in SQL, inside `SECURITY DEFINER`
/// functions — reassembling them in a second client would be a second place for
/// tenant scoping to be got wrong.
final class VendorRetailerRpcDataSource {
  const VendorRetailerRpcDataSource({
    required VendorRetailerListInvoker retailers,
    required VendorRetailerRelationshipInvoker detail,
    required VendorRetailerRelationshipInvoker shops,
  }) : _retailers = retailers,
       _detail = detail,
       _shops = shops;

  /// Builds the data source against a live client.
  factory VendorRetailerRpcDataSource.forClient(SupabaseClient client) {
    return VendorRetailerRpcDataSource(
      retailers: supabaseVendorRetailersInvoker(client),
      detail: supabaseVendorRetailerDetailInvoker(client),
      shops: supabaseVendorRetailerShopsInvoker(client),
    );
  }

  final VendorRetailerListInvoker _retailers;
  final VendorRetailerRelationshipInvoker _detail;
  final VendorRetailerRelationshipInvoker _shops;

  Future<Object?> fetchRetailers() => _retailers();

  Future<Object?> fetchDetail(String relationshipId) => _detail(relationshipId);

  Future<Object?> fetchShops(String relationshipId) => _shops(relationshipId);
}
