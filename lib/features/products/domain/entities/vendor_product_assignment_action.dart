/// What a Vendor is asking the backend to do to one Product/Retailer pairing.
///
/// Three members over **two** deployed functions, and that asymmetry is the
/// whole point of the type.
///
/// ## [assign] and [reactivate] are one call, deliberately
///
/// `public.assign_vendor_product_to_retailer(p_product_id,
/// p_retailer_organization_id)` inserts when no row exists and flips an existing
/// `INACTIVE` row back to `ACTIVE`. It is not two functions and must not be
/// modelled as two: the eligibility gate is identical for both — the Product
/// `ACTIVE`, the Vendor–Retailer relationship `ACTIVE` and the Retailer
/// organization `ACTIVE` — and `vendor_product_retailer_assign_unique_idx` is
/// UNIQUE and **unpartial**, so there is exactly one row per pairing for all
/// time and "insert" versus "flip" is the backend's decision rather than the
/// caller's.
///
/// The two members exist because the two are different **sentences to a
/// reader**. "Assign this Retailer" and "Reactivate this assignment" describe
/// different situations, the second of which has a consequence the first does
/// not ([VendorProductAssignmentAction.reactivate] resets `assigned_at`), and a
/// confirmation dialog that could not tell them apart would have to say
/// something vague about both. So the distinction lives here, in what is spoken,
/// and dies at [isWithdrawal] — which is the only thing the data layer reads.
///
/// ## [withdraw] is a separate function because it has a weaker gate
///
/// `public.unassign_vendor_product_from_retailer(p_product_id,
/// p_retailer_organization_id)` requires **none** of the three statuses to be
/// `ACTIVE`. A Vendor must be able to withdraw a Product from a Retailer it has
/// since suspended, which is exactly when withdrawal matters most, and a status
/// gate there would strand historical assignments as permanently un-endable.
///
/// It sets `status = 'INACTIVE'`. **There is no `DELETE` in either function**
/// and neither browser role holds `DELETE` on the table, so nothing this enum
/// names can erase a pairing — which is why there is no `remove` or `delete`
/// member and no place to add one.
///
/// ## No member is ever sent
///
/// Neither RPC has a status, action, verb or intent parameter. This value picks
/// **which function is called** and never travels inside a payload; a boundary
/// test asserts the two parameter maps directly for exactly that reason.
enum VendorProductAssignmentAction {
  /// Make this Product available at a Retailer that has never held it.
  ///
  /// Reaches `assign_vendor_product_to_retailer`, which inserts a new row.
  assign,

  /// Return a withdrawn assignment to `ACTIVE`.
  ///
  /// Reaches the **same** function as [assign]. The stored row is reused rather
  /// than duplicated, and `assigned_at` is overwritten with the moment of
  /// reactivation — so the date on screen afterwards is when *this* assignment
  /// began, not when the pairing was first created. That consequence is stated
  /// in the confirmation, because it is the one thing a reader would otherwise
  /// get wrong.
  reactivate,

  /// End an assignment that is currently in force.
  ///
  /// Reaches `unassign_vendor_product_from_retailer`. The row survives as
  /// `INACTIVE`, keeps its `assigned_at`, stays visible in the assignment
  /// history and stays counted by `assignment_count`.
  withdraw;

  /// Whether this action reaches the withdrawal RPC rather than the assign one.
  ///
  /// A positive test against the single member that withdraws, so a future
  /// action cannot arrive at "this withdraws" by failing to match something
  /// else. This is the **only** thing the repository asks of this type: the
  /// difference between [assign] and [reactivate] is a difference in wording,
  /// not in wire.
  bool get isWithdrawal => this == withdraw;
}
