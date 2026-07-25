import 'package:equatable/equatable.dart';

import '../../../retailers/domain/entities/vendor_retailer_status.dart';
import 'vendor_product_assignment_status.dart';

/// One row of `public.list_vendor_product_assigned_retailers(uuid)`.
///
/// **One row per existing assignment row, and nothing else.** A Retailer this
/// Vendor manages but has never assigned this product to has no row here — which
/// is the whole difference from the web's editor matrix
/// (`list_vendor_product_retailer_assignments`), which left-joins *from*
/// `vendor_retailers` so an unassigned Retailer appears with a null status.
/// Driven from the assignment table, this read never emits a null
/// [assignmentStatus], so this client never has to decide what one would mean.
///
/// The row count is **exactly** `VendorProductDetail.assignmentCount`.
///
/// ## Why the Retailer status vocabulary is reused rather than redeclared
///
/// [retailerStatus] is `organizations.status` and [relationshipStatus] is
/// `vendor_retailers.status` — the *same two columns* the Vendor Retailer screens
/// already read, under the same two constraints
/// (`organizations_status_allowed`, `vendor_retailers_status_allowed`), both
/// `check (status in ('ACTIVE', 'SUSPENDED', 'DEACTIVATED'))`. So
/// [VendorRetailerStatus] is imported rather than copied: a second enum with
/// identical members would be a second place to add a future value, and only one
/// of the two would be right.
///
/// [assignmentStatus] is **not** folded into it. Its constraint permits two
/// values, not three, and it describes a different row; one shared type would
/// make `SUSPENDED` expressible where it cannot occur, and would let a product
/// status be passed where an assignment status belongs.
///
/// ## Four statuses, four facts, none derived from another
///
/// | Field | Subject | Vocabulary |
/// | --- | --- | --- |
/// | [assignmentStatus] | does this Retailer hold this product now | 2 values |
/// | [relationshipStatus] | this Vendor's relationship with the Retailer | 3, **nullable** |
/// | [retailerStatus] | the Retailer organization itself | 3 values |
/// | the product's own status | the catalogue entry | returned once, by the detail read |
///
/// An **`ACTIVE` assignment against a `SUSPENDED` relationship or a `SUSPENDED`
/// Retailer is a real, reachable state.** Both values are returned exactly as
/// stored so a screen can render that honestly instead of guessing, and nothing
/// in this class infers one from another in either direction.
///
/// ## A missing relationship is a real state, not an error
///
/// The relationship join in SQL is a `LEFT JOIN`, deliberately: an `INNER` join
/// would make an assignment row *vanish* from this list if its `vendor_retailers`
/// row ever ceased to exist, while `assignment_count` — taken from the assignment
/// table alone — would keep counting it. So a missing relationship surfaces as a
/// **null [relationshipId] and null [relationshipStatus]**, with the Retailer's
/// own id, name and status all still present, and the row still part of the
/// count.
///
/// Such a row must still display. It is simply **not cross-linkable**: see
/// [isCrossLinkable].
final class VendorProductAssignedRetailer extends Equatable {
  const VendorProductAssignedRetailer({
    required this.relationshipId,
    required this.retailerOrganizationId,
    required this.retailerName,
    required this.retailerStatus,
    required this.relationshipStatus,
    required this.assignmentStatus,
    required this.assignedAt,
    required this.assignmentUpdatedAt,
  });

  /// `vendor_retailers.id`, or **null** when the relationship row is absent.
  ///
  /// This is the address the shipped Vendor Retailer screens already use —
  /// `list_vendor_retailers()` and `get_vendor_retailer_detail()` both return and
  /// accept it — so a non-null value opens `/vendor/retailers/:relationshipId`
  /// with no second lookup. Returning it is what closes the two-address-space
  /// gap the backend contract records against the editor read.
  ///
  /// Null is **never** an error and is never repaired: nothing fabricates an id,
  /// substitutes [retailerOrganizationId], or drops the row.
  final String? relationshipId;

  /// `organizations.id` of the Retailer. Never null.
  ///
  /// Display and identity only — it is deliberately **never** a route selector
  /// and never sent to any read. It names a tenant some *other* Vendor may also
  /// manage, whereas a relationship id names this Vendor's own view of one
  /// Retailer. Using it to navigate would be addressing a Retailer screen with a
  /// key that screen does not accept.
  final String retailerOrganizationId;

  /// The Retailer organization's display name. Never null, never blank.
  final String retailerName;

  /// The Retailer organization's own lifecycle state. Never null.
  ///
  /// A **separate fact** from [assignmentStatus]: a suspended Retailer may still
  /// hold an active assignment, and both counts include it.
  final VendorRetailerStatus retailerStatus;

  /// This Vendor's relationship with the Retailer, or **null** when the
  /// relationship row is absent.
  ///
  /// Null here always travels with a null [relationshipId] — they are the two
  /// columns the `LEFT JOIN` supplies. It is not a status; it is the absence of
  /// a row, and it is rendered as such rather than as an "Unknown" state that
  /// would imply a relationship exists with an unfamiliar value.
  final VendorRetailerStatus? relationshipStatus;

  /// Whether the Retailer holds this product now. Never null.
  final VendorProductAssignmentStatus assignmentStatus;

  /// When the assignment row was created. UTC.
  ///
  /// The moment the product was *first* assigned to this Retailer. Because the
  /// row survives withdrawal and re-assignment, this is not "when the current
  /// assignment began" and is never worded as such.
  final DateTime assignedAt;

  /// The assignment row's own `updated_at`. UTC.
  ///
  /// **This is not a `withdrawn_at`.** No such column exists, so none is
  /// invented. For an `INACTIVE` row it happens to *be* the moment of
  /// withdrawal — the only write that could follow would flip it back to
  /// `ACTIVE` — but it is named, labelled and spoken as what it is: when the
  /// assignment last changed. Nothing reads a status out of it.
  final DateTime assignmentUpdatedAt;

  /// Whether this row can open the Vendor Retailer detail screen.
  ///
  /// True only when [relationshipId] is present. Deliberately a positive test on
  /// the id itself rather than on any status: a `SUSPENDED` or `DEACTIVATED`
  /// relationship is still addressable and still opens, because the Retailer
  /// detail screen exists precisely to explain such a state. What makes a row
  /// un-openable is the *absence of the row to open*, and nothing else.
  bool get isCrossLinkable => relationshipId != null;

  /// Whether the Vendor–Retailer relationship row is missing entirely.
  ///
  /// The honest description of the state, and the one a screen words as
  /// "Retailer relationship unavailable". It is not a Retailer problem and not an
  /// assignment problem: the assignment is intact and its status is real.
  bool get hasNoRelationship => relationshipId == null;

  @override
  List<Object?> get props => <Object?>[
    relationshipId,
    retailerOrganizationId,
    retailerName,
    retailerStatus,
    relationshipStatus,
    assignmentStatus,
    assignedAt,
    assignmentUpdatedAt,
  ];
}
