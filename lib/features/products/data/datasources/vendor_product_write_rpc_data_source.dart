import 'package:supabase_flutter/supabase_flutter.dart';

/// The three Vendor Product write RPCs, named exactly once each.
///
/// None of them is new. All three shipped with the web catalogue in
/// `20260727210000_vendor_product_catalog_operations.sql`, and two of them were
/// repaired in place — same names, same argument names and order, same return
/// types, same grants — by `20260807090000`. This client reuses them verbatim
/// rather than adding mobile twins, which would be a second definition of "create
/// a product", free to drift from the one the web already calls.
const String createVendorProductRpc = 'create_vendor_product';
const String updateVendorProductRpc = 'update_vendor_product';
const String setVendorProductStatusRpc = 'set_vendor_product_status';

/// The **seven** parameter names these three functions accept between them, and
/// there is no eighth.
///
/// Named as constants so the whole payload vocabulary of this feature's writes is
/// legible in one place, and so a boundary test can assert the set exactly. Note
/// what is not here: no organization, tenant, Vendor, auth-user, profile,
/// membership, actor, role, permission, audit-metadata, Retailer, assignment,
/// price, stock, image, reward or campaign parameter — and no `p_status` on create
/// or edit, and no `p_product_code` on edit.
const String productCodeParameter = 'p_product_code';
const String productNameParameter = 'p_product_name';
const String barcodeParameter = 'p_barcode';
const String brandParameter = 'p_brand';
const String descriptionParameter = 'p_description';
const String writeProductIdParameter = 'p_product_id';
const String statusParameter = 'p_status';

/// Invokes `create_vendor_product(text, text, text, text, text)`.
///
/// Five values, and every one of them is a *product field*. There is no sixth
/// argument for an organization, because the function has none: the Vendor is
/// derived from `auth.uid()` through `get_vendor_super_admin_context()` and a
/// caller cannot nominate one. The initial status is not an argument either — the
/// function inserts `ACTIVE` unconditionally.
///
/// The three optionals are `String?`. Null is what "absent" means all the way
/// down: the function turns `null`, `''` and whitespace-only alike into SQL NULL,
/// so this boundary never has to send a placeholder and never sends `''`.
typedef VendorProductCreateInvoker =
    Future<Object?> Function({
      required String productCode,
      required String productName,
      required String? barcode,
      required String? brand,
      required String? description,
    });

/// Invokes `update_vendor_product(uuid, text, text, text, text)`.
///
/// The id, and the four **mutable display fields**. The absence of a fifth is the
/// security and integrity property together: there is no `p_product_code`, so a
/// code cannot be re-keyed by this boundary even by accident, and no `p_status`,
/// so an edit cannot move a product between `ACTIVE` and `INACTIVE` as a side
/// effect of correcting its name.
typedef VendorProductUpdateInvoker =
    Future<Object?> Function({
      required String productId,
      required String productName,
      required String? barcode,
      required String? brand,
      required String? description,
    });

/// Invokes `set_vendor_product_status(uuid, text)`.
///
/// Two values: which product, and which of the two statuses. The status arrives
/// as a `String` because that is the RPC's parameter type, but the only source of
/// one is `VendorProductStatusChange.code`, whose two members are the only tokens
/// the function's `in ('ACTIVE','INACTIVE')` test accepts.
typedef VendorProductStatusInvoker =
    Future<Object?> Function({
      required String productId,
      required String status,
    });

/// The production invokers.
///
/// The only place in the application that names a Vendor Product **write** RPC
/// and touches the Supabase client for one. Note the call sites: three function
/// names, seven parameter names, and no argument that is not a product field or a
/// product id.
VendorProductCreateInvoker supabaseVendorProductCreateInvoker(
  SupabaseClient client,
) {
  return ({
    required String productCode,
    required String productName,
    required String? barcode,
    required String? brand,
    required String? description,
  }) => client.rpc<Object?>(
    createVendorProductRpc,
    params: <String, Object?>{
      productCodeParameter: productCode,
      productNameParameter: productName,
      barcodeParameter: barcode,
      brandParameter: brand,
      descriptionParameter: description,
    },
  );
}

VendorProductUpdateInvoker supabaseVendorProductUpdateInvoker(
  SupabaseClient client,
) {
  return ({
    required String productId,
    required String productName,
    required String? barcode,
    required String? brand,
    required String? description,
  }) => client.rpc<Object?>(
    updateVendorProductRpc,
    params: <String, Object?>{
      writeProductIdParameter: productId,
      productNameParameter: productName,
      barcodeParameter: barcode,
      brandParameter: brand,
      descriptionParameter: description,
    },
  );
}

VendorProductStatusInvoker supabaseVendorProductStatusInvoker(
  SupabaseClient client,
) {
  return ({required String productId, required String status}) =>
      client.rpc<Object?>(
        setVendorProductStatusRpc,
        params: <String, Object?>{
          writeProductIdParameter: productId,
          statusParameter: status,
        },
      );
}

/// Performs the Vendor Product writes a Vendor Super Admin holding
/// `PRODUCTS_MANAGE` is entitled to.
///
/// Thin by design, exactly like its read counterpart: it performs each call and
/// lets exceptions propagate. Turning an exception into a `Failure` is the
/// repository's job and turning a body into a value is the parser's, so each of
/// the three has one reason to change.
///
/// **No table is ever written here.** There is no `insert`, `update`, `upsert` or
/// `delete` against `vendor_products`, against
/// `vendor_product_retailer_assignments`, or against `audit_logs` — and none
/// against `auth.users` under any spelling. Both product tables have RLS enabled
/// with **zero policies** and no privilege for `anon` or `authenticated`, so a
/// direct write here would not merely be poor layering, it would not work. The
/// audit table is written by the RPCs themselves, inside the same transaction, and
/// a client that added its own row would be recording an event it cannot attest
/// to.
///
/// **No assignment write.** `assign_vendor_product_to_retailer` and
/// `unassign_vendor_product_from_retailer` exist, are gated on a different
/// permission, and are named nowhere in this file.
///
/// **No deletion.** No delete RPC exists in the schema; none is named here.
///
/// **No service-role client, and no key of any kind.** Every call travels on the
/// caller's own token, which is the only reason the functions can derive an
/// identity at all — a service-role connection has no `auth.uid()` and could only
/// ever be refused.
final class VendorProductWriteRpcDataSource {
  const VendorProductWriteRpcDataSource({
    required VendorProductCreateInvoker create,
    required VendorProductUpdateInvoker update,
    required VendorProductStatusInvoker setStatus,
  }) : _create = create,
       _update = update,
       _setStatus = setStatus;

  /// Builds the data source against a live client.
  factory VendorProductWriteRpcDataSource.forClient(SupabaseClient client) {
    return VendorProductWriteRpcDataSource(
      create: supabaseVendorProductCreateInvoker(client),
      update: supabaseVendorProductUpdateInvoker(client),
      setStatus: supabaseVendorProductStatusInvoker(client),
    );
  }

  final VendorProductCreateInvoker _create;
  final VendorProductUpdateInvoker _update;
  final VendorProductStatusInvoker _setStatus;

  /// Returns the raw body — a scalar, which the parser checks is a uuid.
  Future<Object?> createProduct({
    required String productCode,
    required String productName,
    required String? barcode,
    required String? brand,
    required String? description,
  }) => _create(
    productCode: productCode,
    productName: productName,
    barcode: barcode,
    brand: brand,
    description: description,
  );

  /// Returns the raw body, which for a `void` function is empty.
  Future<Object?> updateProduct({
    required String productId,
    required String productName,
    required String? barcode,
    required String? brand,
    required String? description,
  }) => _update(
    productId: productId,
    productName: productName,
    barcode: barcode,
    brand: brand,
    description: description,
  );

  /// Returns the raw body, which for a `void` function is empty.
  Future<Object?> setProductStatus({
    required String productId,
    required String status,
  }) => _setStatus(productId: productId, status: status);
}
