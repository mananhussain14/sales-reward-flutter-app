/// Everything `public.update_vendor_product(...)` accepts beside the product id.
///
/// Four fields — the product's *display* details. What is missing is the contract:
///
/// * **no product code.** It is the canonical key assignments are made against
///   and a future receipt-matching step will resolve, so re-keying an entry in
///   place would silently change what every downstream reference means. The RPC
///   offers no parameter for it and a trigger refuses a direct change. A miscoded
///   product is replaced, not renamed — which is why an edit screen may show the
///   code as read-only context but can never submit it, and why there is no field
///   for it on this class to submit *from*.
/// * **no status.** A status change is a separate operation with a separate RPC,
///   so an edit can never move a product between `ACTIVE` and `INACTIVE` as a
///   side effect of correcting its name.
/// * **no organization, owner, creator or tenant.** All three are immutable by
///   trigger and none is a parameter.
/// * **no assignment field.** An edit touches no assignment row.
///
/// ## Every field is sent on every edit, including the unchanged ones
///
/// The RPC takes all four and writes all four, so this is a whole-record update
/// rather than a patch: a field omitted here would be sent as null and would
/// *clear* the stored value. That is also what makes clearing deliberate — an
/// optional field the operator emptied arrives as null because they emptied it,
/// which is indistinguishable to the backend from "it was never set", exactly as
/// intended.
///
/// A submission in which none of the four differs from what is stored is a
/// **silent success** in SQL: no write, no `updated_at` movement, no audit row.
/// A whitespace-only difference is the same, because normalization runs first.
/// Neither is an error, and this client must not present either as one.
final class VendorProductEdit {
  const VendorProductEdit({
    required this.productName,
    this.barcode,
    this.brand,
    this.description,
  });

  /// `p_product_name`. Required.
  final String productName;

  /// `p_barcode`. Optional and clearable; **null** clears it. Text, never a
  /// number.
  final String? barcode;

  /// `p_brand`. Optional and clearable; null clears it.
  final String? brand;

  /// `p_description`. Optional and clearable; null clears it. Internal line
  /// breaks are preserved.
  final String? description;
}
