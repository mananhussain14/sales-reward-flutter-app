import 'package:equatable/equatable.dart';

import '../../../retailers/domain/entities/vendor_retailer_status.dart';
import '../../../retailers/domain/entities/vendor_retailer_summary.dart';
import 'vendor_product_assigned_retailer.dart';
import 'vendor_product_assignment_status.dart';

/// What this Vendor may do about one Retailer, for one Product, right now.
///
/// A **presentation-side hint**, computed from two trusted reads and never an
/// authorization. The backend re-decides eligibility inside the write, under
/// row locks, against state that may have moved since these values were read —
/// and it is entitled to refuse a selection this enum called
/// [assignable]. Every member therefore describes what the client *last saw*,
/// not what the database will *do*.
enum VendorProductAssignmentCandidateState {
  /// No assignment row exists, and both the Retailer organization and this
  /// Vendor's relationship with it are `ACTIVE`.
  ///
  /// The one state that offers a fresh assignment. It mirrors the deployed
  /// gate exactly — Product `ACTIVE` is checked separately and once, because it
  /// is a property of the Product rather than of any Retailer.
  assignable,

  /// A withdrawn assignment row exists, and the Retailer and the relationship
  /// are both `ACTIVE` again.
  ///
  /// Reactivation goes through the **same** gate as a fresh assignment, so this
  /// differs from [assignable] only in what it says to a reader and in the one
  /// consequence a reader must be told: `assigned_at` is overwritten.
  reactivatable,

  /// An assignment row exists and is in force.
  ///
  /// Not offered for assignment: the backend treats a repeat as a silent no-op,
  /// so a control here would spend a call to change nothing. Withdrawal is
  /// offered from the assignment row itself, where the rest of that row's facts
  /// are.
  alreadyAssigned,

  /// The Retailer organization or this Vendor's relationship with it is not
  /// `ACTIVE`.
  ///
  /// Suspended, deactivated, or carrying a status token this build does not
  /// recognise — all one state, because the deployed function refuses all of
  /// them identically and a client that told them apart would be publishing a
  /// distinction the backend is careful not to make.
  ///
  /// It is **not** a reason to hide the Retailer. A person looking for a
  /// Retailer that is not on the list learns nothing; a person who finds it
  /// with a neutral explanation learns why.
  ineligible,

  /// The pairing exists in history but this Vendor has no `vendor_retailers`
  /// row for the Retailer at all.
  ///
  /// Distinct from [ineligible] on purpose: nothing is suspended and nothing is
  /// wrong with the assignment — there is simply no relationship record to
  /// evaluate, so no assignment can be made and none is offered. The historical
  /// row remains visible, counted, and withdrawable from the assignment list.
  relationshipUnavailable,
}

/// One Retailer, as a choice on the assign surface.
///
/// Composed in [compose] from two already-deployed reads and **no third call**.
///
/// ## There is no relationship id here, and that is deliberate
///
/// This type carries no `relationship_id` field, so an assignment write built
/// from one cannot send a relationship id even by mistake. The write is
/// addressed by [retailerOrganizationId] — the column the assignment table
/// actually stores — and the relationship id is the address the *Retailer
/// detail screen* accepts, which is a different question asked on a different
/// screen.
///
/// ## Nor is a Retailer ever chosen by name
///
/// [retailerName] is display text. Two Retailers may legitimately share a name,
/// and the backend's own ordering breaks that tie on the organization id for
/// exactly that reason. Every selection this type feeds carries
/// [retailerOrganizationId], taken verbatim from a trusted read.
final class VendorProductAssignmentCandidate extends Equatable {
  const VendorProductAssignmentCandidate({
    required this.retailerOrganizationId,
    required this.retailerName,
    required this.retailerStatus,
    required this.relationshipStatus,
    required this.assignmentStatus,
    required this.assignedAt,
    required this.state,
  });

  /// `organizations.id` of the Retailer — the write's only Retailer selector.
  ///
  /// Never rendered. It is an address, and a uuid on screen is noise to a
  /// reader.
  final String retailerOrganizationId;

  /// The Retailer organization's display name.
  final String retailerName;

  /// The Retailer organization's own lifecycle state.
  final VendorRetailerStatus retailerStatus;

  /// This Vendor's relationship with the Retailer, or null when there is no
  /// `vendor_retailers` row to have one.
  ///
  /// Null is the absence of a row rather than an unfamiliar value, and it is
  /// rendered as such — never as an "Unknown" status that would imply a
  /// relationship exists.
  final VendorRetailerStatus? relationshipStatus;

  /// The status of the existing assignment row, or null when the Product has
  /// never been assigned to this Retailer.
  ///
  /// Null and [VendorProductAssignmentStatus.inactive] are **different** facts
  /// and are never collapsed: one means the pairing has no history, the other
  /// means it has history that was ended. The web's editor matrix cannot tell
  /// them apart; this client can, because it is driven from the assignment
  /// table.
  final VendorProductAssignmentStatus? assignmentStatus;

  /// When the existing assignment last became active, or null when there is no
  /// assignment row. UTC.
  ///
  /// For a withdrawn row this is when it was last in force — **not** when the
  /// pairing was first created, because `assigned_at` is overwritten on every
  /// reactivation. It is shown as context on a reactivatable choice and is
  /// never read as a status.
  final DateTime? assignedAt;

  /// What this Vendor may do about this Retailer, as last read.
  final VendorProductAssignmentCandidateState state;

  /// Whether this Retailer can be assigned or reactivated from here.
  ///
  /// A positive test against the two states that offer an action, so a future
  /// state cannot become actionable by failing to match something else. The
  /// Product's own status is **not** consulted: it is one fact about the whole
  /// screen, checked once where it can be explained once, rather than repeated
  /// against every Retailer.
  bool get isActionable =>
      state == VendorProductAssignmentCandidateState.assignable ||
      state == VendorProductAssignmentCandidateState.reactivatable;

  /// Whether the Product has ever been assigned to this Retailer.
  bool get hasHistory => assignmentStatus != null;

  /// Whether [term] matches this Retailer's name, case-insensitively.
  ///
  /// Name only. A search that also matched an id would let somebody select a
  /// Retailer by pasting an address, which is the one selection path this
  /// surface refuses. An empty or whitespace-only term matches everything,
  /// because an empty search is not a filter.
  bool matches(String term) {
    final String needle = term.trim().toLowerCase();
    return needle.isEmpty || retailerName.toLowerCase().contains(needle);
  }

  /// Builds the candidate list from the two trusted reads.
  ///
  /// ## The sources, and why there is no third one
  ///
  /// * [retailers] — `list_vendor_retailers()`, the shipped Vendor Retailer
  ///   directory. It is the **only** honest answer to "which Retailers may this
  ///   Product be assigned to": it is the same `vendor_retailers` set the write
  ///   reaches the Retailer through, scoped to the derived Vendor in SQL, and it
  ///   carries both statuses the assign gate consults.
  /// * [assignments] — `list_vendor_product_assigned_retailers(p_product_id)`,
  ///   which is already loaded for the Product detail screen and is the only
  ///   thing that can distinguish "never assigned" from "assigned and
  ///   withdrawn".
  ///
  /// Neither is a new contract, neither is a table read, and no per-Retailer
  /// call is issued: an eligibility probe per row would be an N+1 over a
  /// question the backend answers inside the write anyway.
  ///
  /// ## Eligibility is mirrored, never invented
  ///
  /// `ACTIVE` Retailer organization **and** `ACTIVE` relationship, exactly as
  /// the deployed function requires, and positive tests against `active` in both
  /// cases so an unrecognised token can never pass. The Product's status is
  /// deliberately absent from this computation — see [isActionable].
  ///
  /// ## Every Retailer appears exactly once
  ///
  /// The directory has at most one row per (Vendor, Retailer) pair and the
  /// assignment read at most one per (Product, Retailer) pair, so a duplicate
  /// cannot arise from a correct backend. It is guarded against anyway, on
  /// [retailerOrganizationId], because a duplicated row on this surface would be
  /// two controls writing the same pairing.
  ///
  /// ## Historical pairings the directory no longer contains
  ///
  /// An assignment row whose Retailer is absent from the directory — the state
  /// the assignment read publishes as a null `relationship_id` — is **kept**,
  /// as [VendorProductAssignmentCandidateState.relationshipUnavailable] or, if
  /// it is still in force, as
  /// [VendorProductAssignmentCandidateState.alreadyAssigned]. Dropping it would
  /// make the assign surface disagree with the history below it about which
  /// Retailers this Product has reached.
  ///
  /// ## Ordering
  ///
  /// Retailer name, then Retailer organization id — the same total order both
  /// backend reads use, so a re-fetching screen sees a stable sequence and two
  /// Retailers sharing a name cannot swap places between requests.
  static List<VendorProductAssignmentCandidate> compose({
    required List<VendorRetailerSummary> retailers,
    required List<VendorProductAssignedRetailer> assignments,
  }) {
    final Map<String, VendorProductAssignedRetailer> byRetailer =
        <String, VendorProductAssignedRetailer>{};
    for (final VendorProductAssignedRetailer assignment in assignments) {
      byRetailer.putIfAbsent(
        assignment.retailerOrganizationId,
        () => assignment,
      );
    }

    final Map<String, VendorProductAssignmentCandidate> composed =
        <String, VendorProductAssignmentCandidate>{};

    for (final VendorRetailerSummary retailer in retailers) {
      composed.putIfAbsent(retailer.retailerOrganizationId, () {
        final VendorProductAssignedRetailer? existing =
            byRetailer[retailer.retailerOrganizationId];
        return VendorProductAssignmentCandidate(
          retailerOrganizationId: retailer.retailerOrganizationId,
          retailerName: retailer.retailerName,
          // The directory's own values, not the assignment row's: both are the
          // same two columns, and the directory is the set the write's
          // eligibility is actually evaluated over.
          retailerStatus: retailer.retailerStatus,
          relationshipStatus: retailer.relationshipStatus,
          assignmentStatus: existing?.assignmentStatus,
          assignedAt: existing?.assignedAt,
          state: _stateFor(
            existing: existing?.assignmentStatus,
            isEligible:
                retailer.retailerStatus.isActive &&
                retailer.relationshipStatus.isActive,
            hasRelationship: true,
          ),
        );
      });
    }

    for (final VendorProductAssignedRetailer assignment in assignments) {
      composed.putIfAbsent(assignment.retailerOrganizationId, () {
        // Reached only for a pairing the directory does not contain, which is
        // the same condition the assignment read publishes as a null
        // relationship id. Nothing is fabricated to fill the gap.
        return VendorProductAssignmentCandidate(
          retailerOrganizationId: assignment.retailerOrganizationId,
          retailerName: assignment.retailerName,
          retailerStatus: assignment.retailerStatus,
          relationshipStatus: assignment.relationshipStatus,
          assignmentStatus: assignment.assignmentStatus,
          assignedAt: assignment.assignedAt,
          state: _stateFor(
            existing: assignment.assignmentStatus,
            isEligible: false,
            hasRelationship: false,
          ),
        );
      });
    }

    final List<VendorProductAssignmentCandidate> ordered = composed.values
        .toList();
    ordered.sort((
      VendorProductAssignmentCandidate a,
      VendorProductAssignmentCandidate b,
    ) {
      final int byName = a.retailerName.compareTo(b.retailerName);
      return byName != 0
          ? byName
          : a.retailerOrganizationId.compareTo(b.retailerOrganizationId);
    });
    return List<VendorProductAssignmentCandidate>.unmodifiable(ordered);
  }

  static VendorProductAssignmentCandidateState _stateFor({
    required VendorProductAssignmentStatus? existing,
    required bool isEligible,
    required bool hasRelationship,
  }) {
    // An assignment already in force outranks every other consideration: a
    // repeat is a backend no-op whatever the statuses around it, so offering
    // one would be offering to spend a call on nothing.
    if (existing != null && existing.isActive) {
      return VendorProductAssignmentCandidateState.alreadyAssigned;
    }
    if (!hasRelationship) {
      return VendorProductAssignmentCandidateState.relationshipUnavailable;
    }
    if (!isEligible) {
      return VendorProductAssignmentCandidateState.ineligible;
    }
    // A positive test against `inactive`: a status token this build does not
    // recognise is not a withdrawn assignment, and guessing that it is would
    // offer a reactivation of something unknown.
    if (existing == VendorProductAssignmentStatus.inactive) {
      return VendorProductAssignmentCandidateState.reactivatable;
    }
    if (existing == null) {
      return VendorProductAssignmentCandidateState.assignable;
    }
    return VendorProductAssignmentCandidateState.ineligible;
  }

  @override
  List<Object?> get props => <Object?>[
    retailerOrganizationId,
    retailerName,
    retailerStatus,
    relationshipStatus,
    assignmentStatus,
    assignedAt,
    state,
  ];
}
