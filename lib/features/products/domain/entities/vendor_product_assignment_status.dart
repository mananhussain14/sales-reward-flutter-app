/// Whether one Retailer currently holds one product.
///
/// The deployed `public.vendor_product_retailer_assignments` table constrains
/// its `status` column with `vendor_product_assignments_status_allowed`, which
/// permits exactly two values — `ACTIVE` and `INACTIVE`.
///
/// ## [inactive] is history, not absence
///
/// Withdrawal in this schema **sets `INACTIVE` and never deletes**
/// (`unassign_vendor_product_from_retailer`), and
/// `vendor_product_retailer_assign_unique_idx` guarantees at most one row per
/// (product, Retailer) *for all time*. So a Retailer assigned, withdrawn and
/// re-assigned is **one** row that flipped status twice, and an [inactive] row
/// is the surviving record that this product was once available there.
///
/// Such a row is returned by `list_vendor_product_assigned_retailers()`, counted
/// by `assignment_count`, and **must be displayed and marked** — not hidden.
/// Hiding it would make ending an assignment look like erasing one, and would
/// leave `assignment_count` unexplainable, since it counts exactly those rows.
///
/// It must also never be worded as "currently assigned". The honest phrasing is
/// *Active assignment* / *Inactive assignment*, which is what
/// `vendor_product_formatting.dart` produces.
///
/// ## It is never inferred, and it never infers
///
/// Four statuses travel on a product screen and they are four different facts
/// about four different rows:
///
/// | Value | Subject |
/// | --- | --- |
/// | this one | is this product assigned to this Retailer **now** |
/// | `relationship_status` | the Vendor–Retailer relationship |
/// | `retailer_status` | the Retailer organization itself |
/// | `VendorProductStatus` | the product's own place in the catalogue |
///
/// An **`ACTIVE` assignment against a `SUSPENDED` relationship is a real,
/// reachable state** — a Vendor may suspend a relationship without withdrawing
/// its products, and the backend's unassign path deliberately does not require
/// an active relationship. So nothing here derives one from another, in either
/// direction, and no date is read as a status: there is no `withdrawn_at`
/// column, and `assignment_updated_at` is named for what it is.
///
/// ## Why this is its own type
///
/// It shares a two-value vocabulary with [VendorProductStatus] and could have
/// been folded into it. It is not, because they are statements about different
/// rows: one type would make "this product is inactive" and "this Retailer no
/// longer holds it" interchangeable at the type level, and the whole point of
/// this screen is that they are not.
///
/// ## Why [unknown] exists, and what it may never do
///
/// A token this build does not recognise means the backend is newer than the
/// app. It degrades to [unknown] and renders neutrally rather than failing the
/// read or dropping the assignment row — losing an assignment because its status
/// is unfamiliar would silently contradict `assignment_count`.
///
/// [unknown] is **never** [active]: it is counted as neither, it never reads as
/// a current assignment, and it enables no navigation or action by itself.
enum VendorProductAssignmentStatus {
  /// The Retailer currently holds this product.
  active('ACTIVE'),

  /// The assignment was withdrawn. The row survives as history and is shown,
  /// labelled, and counted in the total but not in the active total.
  inactive('INACTIVE'),

  /// A value this build does not know. Displayed neutrally, and nothing more.
  unknown('');

  const VendorProductAssignmentStatus(this.code);

  /// The backend token, or the empty string for [unknown].
  final String code;

  /// Maps a backend token to a status, falling back to [unknown].
  ///
  /// Never throws: the caller has already established that a status string is
  /// present — `assignment_status` is `NOT NULL` in the table *and* in the
  /// contract, because the companion read is driven from the assignment table
  /// rather than left-joined to it — and an unrecognised value is a
  /// forward-compatibility case rather than a malformed response.
  static VendorProductAssignmentStatus fromCode(String raw) {
    for (final VendorProductAssignmentStatus status in values) {
      if (status != unknown && status.code == raw) {
        return status;
      }
    }
    return unknown;
  }

  /// Whether this assignment is currently in force.
  ///
  /// A positive test against [active], so neither [inactive] nor a future token
  /// can reach "in force" by failing to match something else.
  bool get isActive => this == active;
}
