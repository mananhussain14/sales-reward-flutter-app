import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/failure.dart';
import '../../../../../core/result/read_result.dart';
import '../../../domain/entities/vendor_product_assigned_retailer.dart';
import '../../../domain/entities/vendor_product_assignment_status.dart';
import '../../../domain/entities/vendor_product_detail.dart';
import '../../../domain/repositories/vendor_product_repository.dart';
import 'vendor_product_write_notice.dart';

part 'vendor_product_detail_state.dart';

/// One product, opened from the catalogue.
///
/// ## The loading order is load-bearing, not a preference
///
/// 1. `get_vendor_product_detail(p_product_id)` — **once**.
/// 2. Only after one valid row is confirmed,
///    `list_vendor_product_assigned_retailers(p_product_id)` — **once**.
///
/// The two are never issued in parallel, and the sequence is not
/// interchangeable. The assignment read answers an **empty list** for a product
/// that has genuinely never been assigned *and* for an id this caller cannot
/// address — indistinguishably, and deliberately so: closing that ambiguity
/// would mean telling a caller whether another Vendor's product exists.
///
/// Zero rows from the **detail** read is what tells them apart. It is the
/// authoritative "this product is not addressable by you", which is why it goes
/// first and why the companion is **not issued at all** when it comes back
/// empty — including for a malformed id from the URL bar, which the repository
/// answers locally without a request ever leaving the device.
///
/// | Case | detail | then assignments | Screen |
/// | --- | --- | --- | --- |
/// | valid product, zero assignments | 1 row | `[]` | detail + "never assigned" |
/// | unknown product | 0 rows | *not called* | unavailable |
/// | another Vendor's product | 0 rows | *not called* | **identical** to unknown |
/// | malformed route id | *not called* | *not called* | **identical** again |
///
/// ## Zero rows is one non-leaking state
///
/// All four of those id cases arrive here as the same `null` and become the same
/// [VendorProductDetailPhase.notFound]. The screen says the product is not
/// available and says nothing further — never that it exists, never that it
/// belongs to somebody else. It is also **not** an outage: `notFound` offers no
/// retry, because retrying cannot change the answer.
///
/// ## The counts are the backend's, and the list is one rendering of them
///
/// `assignment_count` is by construction the number of rows the companion
/// returns, and `active_assignment_count` the number of those whose status is
/// `ACTIVE`. Nothing here recomputes either from the loaded list and presents it
/// as the figure: the counts come from the detail row, the rows come from the
/// companion, and when the two disagree
/// ([VendorProductDetailState.assignmentCountDisagrees]) the screen says so and
/// changes neither.
///
/// ## One instance, provided by the Vendor shell
///
/// The cubit is owned by the shell rather than created per route, for two
/// reasons. It lets the shell's session isolation clear it on a user change — a
/// cubit created below the route would be unreachable from that listener. And
/// [open] is idempotent, so a router refresh or a widget rebuild that re-enters
/// the same product issues no second pair of RPCs.
///
/// ## It is also the read-after-write authority
///
/// The three write RPCs return `uuid`, `void` and `void`. None of them returns a
/// product row, deliberately — so after every successful write the canonical
/// values come from `get_vendor_product_detail` and from nowhere else. This cubit
/// owns that re-read, through [openCreated] for a create and [refreshDetail] for
/// an edit or a status change, which keeps three write cubits from each growing
/// their own copy of it.
///
/// Two properties of [refreshDetail] are load-bearing:
///
/// * **The loaded product stays on screen throughout.** A refresh is not a
///   reload: blanking a product to re-read one field would make a saved change
///   look like a page reset.
/// * **A refresh that fails does not undo the write.** The change is committed;
///   only this client's picture of it is stale. That lands in
///   [VendorProductDetailState.refreshFailure] as a stale-data warning with a
///   Reload — never as "the save failed", and never as a reason to write again.
///
/// **After a product write the assignment rows are not re-read.** A product
/// create, edit or status change touches no assignment row — not even its
/// `updated_at`, which the backend's own suite asserts — so a second assignment
/// read would spend a call to learn nothing, and would replace a good answer for
/// reasons unconnected to it. `assignment_count` and `active_assignment_count`
/// still come from the freshly-read product row, so nothing here fabricates a
/// count after a write.
///
/// **After an assignment write both are re-read**, through
/// [refreshAfterAssignment], because an assign or a withdrawal moves values in
/// both: the history gains or changes a row, and both counts are recomputed by
/// the detail statement. The two answers are applied in **one** emission, so a
/// count and the rows it describes are never rendered a frame apart. Nothing is
/// inserted, removed or re-statused locally on the way — both assignment RPCs
/// return `void`, so the backend is the only authority on what a pairing now
/// looks like, and an optimistic row would be this client inventing one.
final class VendorProductDetailCubit extends Cubit<VendorProductDetailState> {
  VendorProductDetailCubit(this._repository)
    : super(const VendorProductDetailState());

  final VendorProductRepository _repository;

  /// Discriminates the answer this cubit is currently waiting for.
  ///
  /// Every read captures the token it started under and compares it before
  /// emitting. Opening a second product while the first is in flight, or
  /// clearing on a session change, therefore cannot be overwritten by the
  /// earlier answer arriving late — the classic stale-response race, closed the
  /// same way `SessionBloc` closes it.
  int _token = 0;

  /// Loads [productId], unless it is already loaded or loading.
  ///
  /// Idempotent on purpose: widget rebuilds, router refreshes and a second entry
  /// into the same route must not produce a second pair of requests. A
  /// *different* id always starts a fresh load, and so does the same id after
  /// [clear].
  Future<void> open(String productId) {
    if (state.productId == productId &&
        state.phase != VendorProductDetailPhase.initial) {
      return Future<void>.value();
    }
    return _load(productId);
  }

  /// Loads a product that has **just been created**, and remembers that it was.
  ///
  /// Called by the create cubit the moment `create_vendor_product` returns an id,
  /// before the router moves to the product's route — so the canonical read is
  /// already in flight when the detail screen mounts, and that screen's own
  /// [open] recognises the load as its own and issues nothing.
  ///
  /// Deliberately **not** idempotent: a create always names a product this cubit
  /// has never held, and starting fresh is the only correct thing to do with one.
  ///
  /// The notice it sets is what turns "here is a product" into "here is the
  /// product you just created" — an acknowledgement on the canonical screen, made
  /// of values the backend returned rather than values that were typed. It
  /// survives a failed read, which is precisely the case it exists for.
  Future<void> openCreated(String productId) =>
      _load(productId, notice: VendorProductWriteNotice.created);

  /// Re-reads the canonical product row in place, after a successful write.
  ///
  /// [notice] records which write it followed, so the screen can acknowledge it
  /// truthfully; passing null keeps whatever notice is already showing, which is
  /// what the Reload affordance does.
  ///
  /// The assignment rows are **not** re-read: a product create, edit or status
  /// change touches no assignment row — not even its `updated_at` — so a second
  /// call would spend a request to learn nothing.
  Future<void> refreshDetail({VendorProductWriteNotice? notice}) =>
      _refresh(notice: notice, includeAssignments: false);

  /// Re-reads the canonical product row **and** its assignment history, after a
  /// successful assignment write.
  ///
  /// Both reads, because an assignment transition moves values in both: the
  /// history gains or changes a row, and `assignment_count` /
  /// `active_assignment_count` are recomputed by the detail statement. Neither
  /// figure is ever counted from the loaded list, and no row is inserted,
  /// removed or re-statused locally — the write returns `void`, so the backend
  /// is the only authority on what the pairing now looks like.
  ///
  /// **One emission when both succeed.** The two answers are gathered and
  /// applied together, so the count and the rows it describes can never be
  /// rendered a frame apart.
  Future<void> refreshAfterAssignment({VendorProductWriteNotice? notice}) =>
      _refresh(notice: notice, includeAssignments: true);

  /// Re-runs whichever canonical refresh the last one was.
  ///
  /// The Reload affordance a stale-data warning offers. It repeats the *scope*
  /// that failed rather than always re-reading everything: a stale product after
  /// an edit needs the product row, and a stale product after an assignment
  /// needs both. It never re-attempts the write, which has already committed.
  Future<void> reloadCanonical() => _refresh(
    notice: null,
    includeAssignments: state.refreshIncludesAssignments,
  );

  /// A no-op when nothing is open, when the open product is not on screen, or
  /// while a refresh is already running — the last of which is the duplicate-tap
  /// guard for Reload, and the guard that stops two assignment writes settling
  /// into two overlapping re-reads.
  Future<void> _refresh({
    required VendorProductWriteNotice? notice,
    required bool includeAssignments,
  }) async {
    final String? productId = state.productId;
    if (productId == null ||
        state.phase != VendorProductDetailPhase.ready ||
        state.isRefreshing) {
      return;
    }

    final int token = _nextToken();

    emit(
      state.copyWith(
        isRefreshing: true,
        refreshIncludesAssignments: includeAssignments,
        clearRefreshFailure: true,
        notice: notice,
        noticeProductId: notice == null ? null : productId,
      ),
    );

    final ReadResult<VendorProductDetail?> result = await _repository
        .productDetail(productId);

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case ReadSuccess<VendorProductDetail?>(:final VendorProductDetail? value):
        if (value == null) {
          // The product stopped being addressable between the write and the
          // re-read. No product or assignment write can cause that, so this is
          // somebody else's change or a session that is no longer what it was —
          // and the one safe answer is the same non-leaking state a foreign id
          // produces. The stale row is dropped rather than shown as current, and
          // the notice goes with it: acknowledging a change to a product that is
          // no longer there would be the least useful sentence available.
          emit(
            state.copyWith(
              phase: VendorProductDetailPhase.notFound,
              isRefreshing: false,
              clearDetail: true,
              clearNotice: true,
            ),
          );
          return;
        }
        if (!includeAssignments) {
          emit(state.copyWith(detail: value, isRefreshing: false));
          return;
        }
        await _refreshAssignmentsAfter(productId, token, value);

      case ReadFailure<VendorProductDetail?>(:final Failure failure):
        // The write stands. Only the picture of it is stale, so the product
        // already on screen — and, after an assignment write, its existing
        // assignment rows — are kept and the screen says they may be out of
        // date. The assignment companion is not issued at all: the detail read
        // is what establishes that the id is still addressable, and issuing the
        // companion without that answer would be reading assignments for a
        // product this client can no longer vouch for.
        emit(state.copyWith(isRefreshing: false, refreshFailure: failure));
    }
  }

  /// The second half of an assignment refresh: the history, applied together
  /// with the product row the first half returned.
  Future<void> _refreshAssignmentsAfter(
    String productId,
    int token,
    VendorProductDetail detail,
  ) async {
    final ReadResult<List<VendorProductAssignedRetailer>> result =
        await _repository.assignedRetailers(productId);

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case ReadSuccess<List<VendorProductAssignedRetailer>>(
        :final List<VendorProductAssignedRetailer> value,
      ):
        // One emission carrying both answers, so the counts and the rows they
        // describe are never a frame out of step.
        emit(
          state.copyWith(
            detail: detail,
            assignmentsPhase: VendorProductAssignmentsPhase.ready,
            assignments: value,
            clearAssignmentsFailure: true,
            isRefreshing: false,
          ),
        );

      case ReadFailure<List<VendorProductAssignedRetailer>>(
        :final Failure failure,
      ):
        // Partial success, and the state this whole path exists to model: the
        // write committed and the product row is fresh, but the history could
        // not be re-read. The rows already on screen are the last thing the
        // backend said and are kept — replacing a real history with an empty one
        // would make ending an assignment look like erasing every assignment —
        // and the screen says they may be out of date and offers a Reload. It is
        // never worded as a failed write, and it never re-issues one.
        emit(
          state.copyWith(
            detail: detail,
            isRefreshing: false,
            refreshFailure: failure,
          ),
        );
    }
  }

  /// Re-runs the whole sequence for the currently open product.
  ///
  /// Offered only for an operational failure. There is no retry from
  /// [VendorProductDetailPhase.notFound]: the backend already answered, and it
  /// will answer the same way.
  Future<void> retryDetail() {
    final String? productId = state.productId;
    if (productId == null || state.isDetailLoading) {
      return Future<void>.value();
    }
    return _load(productId);
  }

  /// Re-runs **only** the assignment read, leaving the loaded product on screen.
  ///
  /// An assignment failure degrades that section alone — the product's name,
  /// code, barcode, brand, description, status, both counts and its dates came
  /// from a call that succeeded and are still true, and re-reading the detail to
  /// recover a companion would throw away a good answer to fix a different one.
  Future<void> retryAssignments() {
    final String? productId = state.productId;
    if (productId == null ||
        state.phase != VendorProductDetailPhase.ready ||
        state.assignmentsPhase == VendorProductAssignmentsPhase.loading) {
      return Future<void>.value();
    }
    return _loadAssignments(productId, _nextToken());
  }

  /// Drops the open product and its assignment rows.
  ///
  /// Called when the signed-in person changes. Everything here is private Vendor
  /// data — the product's own fields, its counts, and the names and statuses of
  /// the Retailers it is assigned to. The token is advanced first, so an answer
  /// already in flight for the previous person cannot repopulate the state after
  /// it has been emptied.
  void clear() {
    _nextToken();
    emit(const VendorProductDetailState());
  }

  int _nextToken() => ++_token;

  Future<void> _load(
    String productId, {
    VendorProductWriteNotice? notice,
  }) async {
    final int token = _nextToken();

    // A whole fresh state, so nothing from the previously open product survives
    // into this one — including a write notice, which belongs to exactly one
    // product and is re-supplied here only when this load *is* that product's.
    emit(
      VendorProductDetailState(
        productId: productId,
        phase: VendorProductDetailPhase.loading,
        notice: notice,
        noticeProductId: notice == null ? null : productId,
      ),
    );

    final ReadResult<VendorProductDetail?> result = await _repository
        .productDetail(productId);

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case ReadSuccess<VendorProductDetail?>(:final VendorProductDetail? value):
        if (value == null) {
          // Not addressable. One state for "no such id", "another Vendor's id",
          // "an id from another table" and "malformed id" alike — and no
          // assignment read, because an empty assignment list would look like a
          // product that has never been assigned.
          emit(state.copyWith(phase: VendorProductDetailPhase.notFound));
          return;
        }
        emit(
          state.copyWith(phase: VendorProductDetailPhase.ready, detail: value),
        );
        await _loadAssignments(productId, token);

      case ReadFailure<VendorProductDetail?>(:final Failure failure):
        emit(
          state.copyWith(
            phase: VendorProductDetailPhase.failed,
            failure: failure,
          ),
        );
    }
  }

  Future<void> _loadAssignments(String productId, int token) async {
    emit(
      state.copyWith(
        assignmentsPhase: VendorProductAssignmentsPhase.loading,
        clearAssignmentsFailure: true,
      ),
    );

    final ReadResult<List<VendorProductAssignedRetailer>> result =
        await _repository.assignedRetailers(productId);

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case ReadSuccess<List<VendorProductAssignedRetailer>>(
        :final List<VendorProductAssignedRetailer> value,
      ):
        emit(
          state.copyWith(
            assignmentsPhase: VendorProductAssignmentsPhase.ready,
            assignments: value,
            clearAssignmentsFailure: true,
          ),
        );

      case ReadFailure<List<VendorProductAssignedRetailer>>(
        :final Failure failure,
      ):
        emit(
          state.copyWith(
            assignmentsPhase: VendorProductAssignmentsPhase.failed,
            assignmentsFailure: failure,
          ),
        );
    }
  }
}
