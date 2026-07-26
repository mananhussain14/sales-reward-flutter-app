import 'package:supabase_flutter/supabase_flutter.dart';

/// The two Vendor Product **assignment** write RPCs, named exactly once each.
///
/// Neither is new. Both shipped with the web catalogue in
/// `20260727210000_vendor_product_catalog_operations.sql` and were reused
/// unchanged — no migration, no new function, no modified function — by the
/// backend milestone that specified them for this client. Adding mobile twins
/// would be a second definition of "assign a product", free to drift from the
/// one the web already calls.
const String assignVendorProductToRetailerRpc =
    'assign_vendor_product_to_retailer';
const String unassignVendorProductFromRetailerRpc =
    'unassign_vendor_product_from_retailer';

/// The **two** parameter names these two functions accept between them, and
/// there is no third.
///
/// Named as constants so this feature's whole assignment payload vocabulary is
/// legible in one place, and so a boundary test can assert the set exactly. Note
/// what is not here: no organization, tenant, Vendor, auth-user, profile,
/// membership, actor, role, permission or audit-metadata parameter; no
/// relationship id; no assignment id; and no status, note, effective date,
/// price, quantity or idempotency key — the functions have parameters for none
/// of them.
///
/// [assignmentProductIdParameter] is spelled the same as the reads' selector
/// because it *is* the same selector. It is declared separately rather than
/// imported so that this file states its own payload without depending on
/// another boundary's vocabulary.
const String assignmentProductIdParameter = 'p_product_id';
const String assignmentRetailerParameter = 'p_retailer_organization_id';

/// Invokes either assignment function: `(uuid, uuid) returns void`.
///
/// One typedef for both, because the two signatures are byte-identical and a
/// second one would only create a place for them to diverge. Which function is
/// reached is decided by the data source's two methods below, and never by a
/// value inside the payload.
///
/// Two `String`s, and both are **addresses**. No identity travels beside them:
/// the Vendor is derived from `auth.uid()` through
/// `get_vendor_super_admin_context()`, the Product is matched on its own id
/// *and* that derived Vendor, and the Retailer is reached only through the
/// derived Vendor's own `vendor_retailers` row. Holding either id therefore
/// grants nothing.
typedef VendorProductAssignmentInvoker =
    Future<Object?> Function({
      required String productId,
      required String retailerOrganizationId,
    });

/// The production invokers.
///
/// The only place in the application that names an assignment RPC and touches
/// the Supabase client for one. Note the call sites: two function names, two
/// parameter names, and no argument that is not one of the two addresses.
VendorProductAssignmentInvoker supabaseVendorProductAssignInvoker(
  SupabaseClient client,
) {
  return ({
    required String productId,
    required String retailerOrganizationId,
  }) => client.rpc<Object?>(
    assignVendorProductToRetailerRpc,
    params: <String, Object?>{
      assignmentProductIdParameter: productId,
      assignmentRetailerParameter: retailerOrganizationId,
    },
  );
}

VendorProductAssignmentInvoker supabaseVendorProductWithdrawInvoker(
  SupabaseClient client,
) {
  return ({
    required String productId,
    required String retailerOrganizationId,
  }) => client.rpc<Object?>(
    unassignVendorProductFromRetailerRpc,
    params: <String, Object?>{
      assignmentProductIdParameter: productId,
      assignmentRetailerParameter: retailerOrganizationId,
    },
  );
}

/// Performs the two Product-to-Retailer assignment writes a Vendor Super Admin
/// holding `PRODUCT_RETAILER_ASSIGN` is entitled to.
///
/// Thin by design, exactly like its read and Product-write counterparts: it
/// performs each call and lets exceptions propagate. Turning an exception into a
/// `Failure` is the repository's job, so each has one reason to change.
///
/// ## A third data source, for a different permission
///
/// This is deliberately not a pair of methods on the Product write source. Both
/// functions here are gated on **`PRODUCT_RETAILER_ASSIGN`**, which the backend
/// proved — by removing each seeded mapping in turn — is *distinct from*
/// `PRODUCTS_MANAGE`: a caller holding only `PRODUCTS_MANAGE` is refused both of
/// these, and a caller holding only `PRODUCT_RETAILER_ASSIGN` is refused
/// `set_vendor_product_status`. Two entitlements, two payload vocabularies, two
/// files — so each one's boundary test can assert its own parameter set exactly.
///
/// This client neither names, sends, inspects nor displays either permission
/// code. It calls the function and handles the refusal.
///
/// **No table is ever written here.** There is no `insert`, `update`, `upsert`
/// or `delete` against `vendor_product_retailer_assignments`, against
/// `vendor_products`, against `vendor_retailers`, against `organizations` or
/// against `audit_logs`. The assignment table has RLS enabled with **zero
/// policies** and no privilege for `anon` or `authenticated`, so a direct write
/// here would not merely be poor layering — it would not work. The audit rows
/// are written by the functions themselves, inside the same transaction, and a
/// client that added its own would be recording an event it cannot attest to.
///
/// **No deletion, ever.** Neither deployed function contains a `DELETE` or a
/// `TRUNCATE`, no delete RPC exists in the schema, and neither browser role
/// holds `DELETE` on the assignment table. Withdrawal sets a status; the row
/// survives.
///
/// **No bulk operation.** Each method addresses exactly one pairing. There is no
/// assign-all, no array parameter and no loop here — the backend offers no bulk
/// function, and building one out of N calls would be inventing a transaction
/// boundary that does not exist.
///
/// **No service-role client, and no key of any kind.** Every call travels on the
/// caller's own token, which is the only reason the functions can derive an
/// identity at all — a service-role connection has no `auth.uid()` and could
/// only ever be refused.
final class VendorProductAssignmentRpcDataSource {
  const VendorProductAssignmentRpcDataSource({
    required VendorProductAssignmentInvoker assign,
    required VendorProductAssignmentInvoker withdraw,
  }) : _assign = assign,
       _withdraw = withdraw;

  /// Builds the data source against a live client.
  factory VendorProductAssignmentRpcDataSource.forClient(
    SupabaseClient client,
  ) {
    return VendorProductAssignmentRpcDataSource(
      assign: supabaseVendorProductAssignInvoker(client),
      withdraw: supabaseVendorProductWithdrawInvoker(client),
    );
  }

  final VendorProductAssignmentInvoker _assign;
  final VendorProductAssignmentInvoker _withdraw;

  /// `assign_vendor_product_to_retailer(uuid, uuid)`.
  ///
  /// Creates the assignment when none exists and reactivates a withdrawn one —
  /// one call for both, because the deployed function decides which. Returns the
  /// raw body, which for a `void` function is empty.
  Future<Object?> assign({
    required String productId,
    required String retailerOrganizationId,
  }) => _assign(
    productId: productId,
    retailerOrganizationId: retailerOrganizationId,
  );

  /// `unassign_vendor_product_from_retailer(uuid, uuid)`.
  ///
  /// Sets the existing row `INACTIVE`. Returns the raw body, which for a `void`
  /// function is empty.
  Future<Object?> withdraw({
    required String productId,
    required String retailerOrganizationId,
  }) => _withdraw(
    productId: productId,
    retailerOrganizationId: retailerOrganizationId,
  );
}
