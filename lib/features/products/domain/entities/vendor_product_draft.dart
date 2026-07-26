/// Everything `public.create_vendor_product(...)` accepts, and nothing else.
///
/// Five fields, in the RPC's own order. The absence of everything else is the
/// point, and it is enforced by the type rather than by review:
///
/// * **no organization, tenant or Vendor id** — the function derives the Vendor
///   from `auth.uid()` through `get_vendor_super_admin_context()`, and there is no
///   parameter to nominate one;
/// * **no auth user, profile or membership id** — `created_by_profile_id` is
///   taken from `auth.uid()` inside the function and from nowhere else;
/// * **no role or permission code** — the `PRODUCTS_MANAGE` gate is applied in
///   SQL, and this client neither knows nor sends the code;
/// * **no initial status** — a new product is `ACTIVE`, unconditionally, decided
///   by the function. The web has never offered that choice, so neither does
///   this;
/// * **no Retailer or assignment field** — create writes no assignment row, and
///   assignment writes are a separate milestone on a separate permission;
/// * **no price, stock, image, reward, incentive or campaign field** — none of
///   those columns exists anywhere in the schema.
///
/// The five values here are already normalized by the rules in
/// `VendorProductInput`. That normalization is a courtesy to the operator, not an
/// authority: the function re-normalizes and re-validates every one of them from
/// scratch.
final class VendorProductDraft {
  const VendorProductDraft({
    required this.productCode,
    required this.productName,
    this.barcode,
    this.brand,
    this.description,
  });

  /// `p_product_code`. Required, administrator-supplied, and **immutable once
  /// stored** — there is no code parameter on the edit RPC and a trigger refuses
  /// a direct change. Upper-cased before it gets here, and upper-cased again in
  /// SQL.
  final String productCode;

  /// `p_product_name`. Required.
  final String productName;

  /// `p_barcode`. Optional; **null** when absent, never `''`.
  ///
  /// A `String?` and never a number: `int` would drop a leading zero and a
  /// 14-digit GTIN exceeds what a `double` can hold exactly.
  final String? barcode;

  /// `p_brand`. Optional; null when absent.
  final String? brand;

  /// `p_description`. Optional; null when absent. Internal line breaks are
  /// preserved — the backend trims only the ends of this one field.
  final String? description;
}
