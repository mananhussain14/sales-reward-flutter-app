part of 'vendor_product_detail_cubit.dart';

/// Where the detail read has reached.
enum VendorProductDetailPhase {
  /// Nothing is open.
  initial,

  /// `get_vendor_product_detail` is in flight.
  loading,

  /// One addressable product is on screen.
  ready,

  /// The backend returned **zero rows**.
  ///
  /// One state for an unknown id, another Vendor's id, an id belonging to some
  /// other table and a malformed id alike. Not an error, not an outage, and not
  /// retryable: the backend answered, and it will answer the same way again.
  notFound,

  /// The read did not produce an answer — a denial, an expired session, a
  /// timeout, or a body that could not be understood.
  failed,
}

/// Where the companion assignment read has reached.
///
/// Tracked separately from [VendorProductDetailPhase] because the two degrade
/// independently: a product whose assignments could not be loaded still has a
/// name, a code, a status and two counts that came from a call which succeeded.
enum VendorProductAssignmentsPhase { initial, loading, ready, failed }

/// One open product, and the Retailers it is assigned to.
final class VendorProductDetailState extends Equatable {
  const VendorProductDetailState({
    this.productId,
    this.phase = VendorProductDetailPhase.initial,
    this.detail,
    this.failure,
    this.assignmentsPhase = VendorProductAssignmentsPhase.initial,
    this.assignments = const <VendorProductAssignedRetailer>[],
    this.assignmentsFailure,
    this.isRefreshing = false,
    this.refreshIncludesAssignments = false,
    this.refreshFailure,
    this.notice,
    this.noticeProductId,
  });

  /// The product currently open, or null when nothing is.
  ///
  /// Held so a retry knows what to re-read, and so
  /// [VendorProductDetailCubit.open] can recognise a repeat. It is **not**
  /// rendered as a field: an internal identifier on screen is noise to a Vendor,
  /// and the product code is the identifier a person actually uses.
  final String? productId;

  final VendorProductDetailPhase phase;

  /// The loaded row, present only in [VendorProductDetailPhase.ready].
  final VendorProductDetail? detail;

  /// Why the detail read failed. A discriminant; never the backend's message.
  final Failure? failure;

  final VendorProductAssignmentsPhase assignmentsPhase;

  /// The assignment rows, in the backend's
  /// `retailer_name, retailer_organization_id` order. Not re-sorted, not
  /// de-duplicated, and **not filtered** — an `INACTIVE` assignment is part of
  /// this list and of the total count, and removing it would make withdrawing an
  /// assignment look like erasing one.
  final List<VendorProductAssignedRetailer> assignments;

  final Failure? assignmentsFailure;

  /// A canonical re-read is in flight over a product that is still on screen.
  ///
  /// Distinct from [VendorProductDetailPhase.loading], which replaces the whole
  /// page: this one drives a spinner beside the product while every one of its
  /// fields stays legible, because a saved change must not look like a page reset.
  /// It is also the duplicate-tap guard for Reload.
  final bool isRefreshing;

  /// Whether the canonical refresh in progress — or the last one that ran —
  /// covers the assignment history as well as the product row.
  ///
  /// Held so a Reload offered after a partial success repeats the **same
  /// scope**. A stale product after an edit needs the product row; a stale
  /// product after an assignment needs both, and reloading only half of it would
  /// leave the count and the rows it describes disagreeing for a second time.
  final bool refreshIncludesAssignments;

  /// Why the canonical re-read after a successful write did not answer.
  ///
  /// **This is never a failed write.** The mutation is committed — the RPC
  /// answered before this read was issued — and the only casualty is the freshness
  /// of what is displayed. The screen therefore keeps [detail], says it may be out
  /// of date, and offers a Reload. A discriminant, never the backend's message.
  final Failure? refreshFailure;

  /// The write this screen has just performed, if any.
  final VendorProductWriteNotice? notice;

  /// The product [notice] is about.
  ///
  /// Held so an acknowledgement can never outlive its subject. A notice is only
  /// rendered while it names the product on screen, which is what makes "Product
  /// created" a permanently true sentence rather than one that starts describing
  /// whatever the reader opened next.
  final String? noticeProductId;

  /// The acknowledgement to show, or null when there is none for this product.
  VendorProductWriteNotice? get currentNotice =>
      notice != null && noticeProductId != null && noticeProductId == productId
      ? notice
      : null;

  bool get isDetailLoading => phase == VendorProductDetailPhase.loading;

  /// A real, successful "this product has never been assigned to any Retailer" —
  /// distinguishable from "this product is not addressable by you" only because
  /// the detail read came back first.
  bool get hasNoAssignments =>
      phase == VendorProductDetailPhase.ready &&
      assignmentsPhase == VendorProductAssignmentsPhase.ready &&
      assignments.isEmpty;

  /// The assignment rows currently in force.
  ///
  /// Presentation input only — used to group the section, never to report a
  /// figure. The authoritative active count is
  /// `detail.activeAssignmentCount`, which comes from the same statement as the
  /// total and cannot disagree with the catalogue's number.
  List<VendorProductAssignedRetailer> get activeAssignments => assignments
      .where(
        (VendorProductAssignedRetailer a) =>
            a.assignmentStatus == VendorProductAssignmentStatus.active,
      )
      .toList(growable: false);

  /// Assignment rows that exist but are not in force.
  ///
  /// A positive test against `inactive`, so a status token this build does not
  /// recognise falls into neither group and is still rendered in the list —
  /// which is what keeps the rendered rows equal in number to
  /// `assignment_count`.
  List<VendorProductAssignedRetailer> get inactiveAssignments => assignments
      .where(
        (VendorProductAssignedRetailer a) =>
            a.assignmentStatus == VendorProductAssignmentStatus.inactive,
      )
      .toList(growable: false);

  /// Whether any loaded assignment has lost its Vendor–Retailer relationship
  /// row.
  ///
  /// Such rows are shown and counted like any other; they are simply not
  /// cross-linkable. This exists so the section can explain the state once,
  /// above the rows, rather than leaving a reader to wonder why one row has no
  /// action.
  bool get hasUnlinkedAssignments =>
      assignments.any((VendorProductAssignedRetailer a) => a.hasNoRelationship);

  /// The loaded row disagrees with the companion about how many assignments
  /// exist.
  ///
  /// The backend computes `assignment_count` over the same table with the same
  /// predicate the companion is driven from, so it is *by construction* the
  /// number of rows the companion returns, and pgTAP asserts the invariant. A
  /// mismatch therefore means the two reads saw different states — most
  /// plausibly an assignment change between them.
  ///
  /// It is surfaced as a note and nothing more: **every returned row is still
  /// shown and both counts are still reported unchanged.** Dropping rows to
  /// match the number, or adjusting the number to match the rows, would each
  /// fabricate agreement the backend did not send.
  bool get assignmentCountDisagrees =>
      phase == VendorProductDetailPhase.ready &&
      assignmentsPhase == VendorProductAssignmentsPhase.ready &&
      detail != null &&
      detail!.assignmentCount != assignments.length;

  VendorProductDetailState copyWith({
    String? productId,
    VendorProductDetailPhase? phase,
    VendorProductDetail? detail,
    bool clearDetail = false,
    Failure? failure,
    VendorProductAssignmentsPhase? assignmentsPhase,
    List<VendorProductAssignedRetailer>? assignments,
    Failure? assignmentsFailure,
    bool clearAssignmentsFailure = false,
    bool? isRefreshing,
    bool? refreshIncludesAssignments,
    Failure? refreshFailure,
    bool clearRefreshFailure = false,
    VendorProductWriteNotice? notice,
    String? noticeProductId,
    bool clearNotice = false,
  }) {
    return VendorProductDetailState(
      productId: productId ?? this.productId,
      phase: phase ?? this.phase,
      detail: clearDetail ? null : (detail ?? this.detail),
      failure: failure ?? this.failure,
      assignmentsPhase: assignmentsPhase ?? this.assignmentsPhase,
      assignments: assignments ?? this.assignments,
      assignmentsFailure: clearAssignmentsFailure
          ? null
          : (assignmentsFailure ?? this.assignmentsFailure),
      isRefreshing: isRefreshing ?? this.isRefreshing,
      refreshIncludesAssignments:
          refreshIncludesAssignments ?? this.refreshIncludesAssignments,
      refreshFailure: clearRefreshFailure
          ? null
          : (refreshFailure ?? this.refreshFailure),
      notice: clearNotice ? null : (notice ?? this.notice),
      noticeProductId: clearNotice
          ? null
          : (noticeProductId ?? this.noticeProductId),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    productId,
    phase,
    detail,
    failure,
    assignmentsPhase,
    assignments,
    assignmentsFailure,
    isRefreshing,
    refreshIncludesAssignments,
    refreshFailure,
    notice,
    noticeProductId,
  ];
}
