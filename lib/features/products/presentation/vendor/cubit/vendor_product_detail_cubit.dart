import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/failure.dart';
import '../../../../../core/result/read_result.dart';
import '../../../domain/entities/vendor_product_assigned_retailer.dart';
import '../../../domain/entities/vendor_product_assignment_status.dart';
import '../../../domain/entities/vendor_product_detail.dart';
import '../../../domain/repositories/vendor_product_repository.dart';

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

  Future<void> _load(String productId) async {
    final int token = _nextToken();

    emit(
      VendorProductDetailState(
        productId: productId,
        phase: VendorProductDetailPhase.loading,
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
