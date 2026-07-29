import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/failure.dart';
import '../../../domain/entities/vendor_retailer_detail.dart';
import '../../../domain/entities/vendor_retailer_shop.dart';
import '../../../domain/repositories/vendor_retailer_repository.dart';
import '../../../domain/repositories/vendor_retailer_result.dart';
import 'vendor_retailer_lifecycle_notice.dart';

part 'vendor_retailer_detail_state.dart';

/// One Retailer, opened from the directory.
///
/// ## The loading order is load-bearing, not a preference
///
/// 1. `get_vendor_retailer_detail(p_relationship_id)` — **once**.
/// 2. Only after a row comes back, `list_vendor_retailer_shops(p_relationship_id)`
///    — **once**.
///
/// The shop read answers an empty list for a shop-less Retailer of the caller's
/// own *and* for a relationship that is not addressable by them. The detail read
/// is what tells those apart: zero rows **there** is the authoritative "not
/// addressable by you". Loading shops first, or in parallel, would leave the
/// screen unable to distinguish "this Retailer has no shops" from "this
/// Retailer is not yours", and the safe reading of the second is not "no shops".
///
/// So when the detail is inaccessible the shop read is **not issued at all**.
///
/// ## Zero rows is one non-leaking state
///
/// An unknown relationship id, another Vendor's relationship id and a malformed
/// one all arrive here as the same `null` and become the same
/// [VendorRetailerDetailPhase.notFound]. The screen says the Retailer is not
/// available to this account and says nothing about whether it exists — a
/// distinguishable message would confirm that another Vendor's relationship
/// exists, and by sweeping ids, roughly how many.
///
/// It is also **not** an outage: `notFound` offers no retry, because retrying
/// cannot change the answer.
///
/// ## One instance, provided by the Vendor shell
///
/// The cubit is owned by the shell rather than created per route, for two
/// reasons. It lets the shell's session isolation clear it on a user change —
/// a cubit created below the route would be unreachable from that listener. And
/// [open] is idempotent, so a router refresh or a widget rebuild that re-enters
/// the same relationship issues no second pair of RPCs.
///
/// ## It is also the read-after-write authority for the lifecycle control
///
/// `set_vendor_retailer_status` returns four scalars describing what it did — it
/// does **not** return a Retailer row. So after every committed lifecycle write
/// the canonical statuses come from `get_vendor_retailer_detail` and from
/// nowhere else, through [refreshAfterLifecycleChange]. Nothing patches a loaded
/// [VendorRetailerDetail] in place, and no badge is flipped ahead of that read.
///
/// Three properties of that refresh are load-bearing:
///
/// * **The loaded Retailer stays on screen throughout.** A refresh is not a
///   reload: blanking a Retailer to re-read two columns would make a saved
///   change look like a page reset.
/// * **A refresh that fails does not undo the write.** The change is committed;
///   only this client's picture of it is stale. That lands in
///   [VendorRetailerDetailState.refreshFailure] as a stale-data warning with a
///   Reload — never as "the change failed", and never as a reason to write
///   again.
/// * **The shops are not re-read.** A lifecycle change moves
///   `organizations.status` and `vendor_retailers.status` and nothing else — no
///   shop row is touched, not even its `updated_at` — so a second call would
///   spend a request to learn nothing, and would replace a good answer for
///   reasons unconnected to it.
final class VendorRetailerDetailCubit extends Cubit<VendorRetailerDetailState> {
  VendorRetailerDetailCubit(this._repository)
    : super(const VendorRetailerDetailState());

  final VendorRetailerRepository _repository;

  /// Discriminates the answer this cubit is currently waiting for.
  ///
  /// Every read captures the token it started under and compares it before
  /// emitting. Opening a second Retailer while the first is in flight, or
  /// clearing on a session change, therefore cannot be overwritten by the
  /// earlier answer arriving late — the classic stale-response race, closed the
  /// same way `SessionBloc` closes it.
  int _token = 0;

  /// Loads [relationshipId], unless it is already loaded or loading.
  ///
  /// Idempotent on purpose: widget rebuilds, router refreshes and a second entry
  /// into the same route must not produce a second pair of requests. A
  /// *different* id always starts a fresh load, and so does the same id after
  /// [clear].
  Future<void> open(String relationshipId) {
    if (state.relationshipId == relationshipId &&
        state.phase != VendorRetailerDetailPhase.initial) {
      return Future<void>.value();
    }
    return _load(relationshipId);
  }

  /// Re-runs the whole sequence for the currently open Retailer.
  ///
  /// Offered only for an operational failure. There is no retry from
  /// [VendorRetailerDetailPhase.notFound]: the backend already answered, and it
  /// will answer the same way.
  Future<void> retryDetail() {
    final String? relationshipId = state.relationshipId;
    if (relationshipId == null || state.isDetailLoading) {
      return Future<void>.value();
    }
    return _load(relationshipId);
  }

  /// Re-runs only the shop read, leaving the loaded detail on screen.
  ///
  /// A shop failure degrades the shop section alone — the Retailer's identity,
  /// statuses and counts came from a call that succeeded and are still true.
  Future<void> retryShops() {
    final String? relationshipId = state.relationshipId;
    if (relationshipId == null ||
        state.phase != VendorRetailerDetailPhase.ready ||
        state.shopsPhase == VendorRetailerShopsPhase.loading) {
      return Future<void>.value();
    }
    return _loadShops(relationshipId, _nextToken());
  }

  /// Re-reads the canonical Retailer row in place, after a committed lifecycle
  /// write.
  ///
  /// [notice] records which outcome it followed, so the screen can acknowledge
  /// it truthfully; passing null keeps whatever notice is already showing, which
  /// is what the Reload affordance does.
  ///
  /// The shops are **not** re-read: a lifecycle change touches no shop row, so a
  /// second call would learn nothing.
  ///
  /// A no-op when nothing is open, when the open Retailer is not on screen, or
  /// while a refresh is already running — the last of which is the duplicate-tap
  /// guard for Reload.
  Future<void> refreshAfterLifecycleChange({
    VendorRetailerLifecycleNotice? notice,
  }) async {
    final String? relationshipId = state.relationshipId;
    if (relationshipId == null ||
        state.phase != VendorRetailerDetailPhase.ready ||
        state.isRefreshing) {
      return;
    }

    final int token = _nextToken();

    emit(
      state.copyWith(
        isRefreshing: true,
        clearRefreshFailure: true,
        notice: notice,
        noticeRelationshipId: notice == null ? null : relationshipId,
      ),
    );

    final VendorRetailerResult<VendorRetailerDetail?> result = await _repository
        .retailerDetail(relationshipId);

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case VendorRetailerReadSuccess<VendorRetailerDetail?>(
        :final VendorRetailerDetail? value,
      ):
        if (value == null) {
          // The relationship stopped being addressable between the write and
          // the re-read. A lifecycle change cannot cause that — it moves two
          // status columns and deletes nothing — so this is somebody else's
          // change or a session that is no longer what it was, and the one safe
          // answer is the same non-leaking state a foreign id produces. The
          // stale row is dropped rather than shown as current, and the notice
          // goes with it: acknowledging a change to a Retailer that is no
          // longer there would be the least useful sentence available.
          emit(
            state.copyWith(
              phase: VendorRetailerDetailPhase.notFound,
              isRefreshing: false,
              clearDetail: true,
              clearNotice: true,
            ),
          );
          return;
        }
        emit(state.copyWith(detail: value, isRefreshing: false));

      case VendorRetailerReadFailure<VendorRetailerDetail?>(
        :final Failure failure,
      ):
        // The write stands. Only the picture of it is stale, so the Retailer
        // already on screen is kept and the screen says it may be out of date.
        // It is never worded as a failed write, and it never re-issues one.
        emit(state.copyWith(isRefreshing: false, refreshFailure: failure));
    }
  }

  /// Re-runs the canonical refresh. The Reload affordance a stale-data warning
  /// offers.
  ///
  /// It never re-attempts the write, which has already committed, and it keeps
  /// whatever notice is showing.
  Future<void> reloadCanonical() => refreshAfterLifecycleChange();

  /// Drops the open Retailer and its shops.
  ///
  /// Called when the signed-in person changes, so one Vendor's Retailer can
  /// never remain on screen for the next. The token is advanced first, so an
  /// answer already in flight for the previous person cannot repopulate the
  /// state after it has been emptied — including a lifecycle refresh and the
  /// notice riding on it, which would otherwise leave a "Retailer deactivated"
  /// acknowledgement over somebody else's Retailer.
  void clear() {
    _nextToken();
    emit(const VendorRetailerDetailState());
  }

  int _nextToken() => ++_token;

  Future<void> _load(String relationshipId) async {
    final int token = _nextToken();

    emit(
      VendorRetailerDetailState(
        relationshipId: relationshipId,
        phase: VendorRetailerDetailPhase.loading,
      ),
    );

    final VendorRetailerResult<VendorRetailerDetail?> result = await _repository
        .retailerDetail(relationshipId);

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case VendorRetailerReadSuccess<VendorRetailerDetail?>(
        :final VendorRetailerDetail? value,
      ):
        if (value == null) {
          // Not addressable by this caller. One state for "no such id",
          // "somebody else's id" and "malformed id" alike — and no shop read,
          // because an empty shop list would look like a Retailer with no
          // shops.
          emit(state.copyWith(phase: VendorRetailerDetailPhase.notFound));
          return;
        }
        emit(
          state.copyWith(phase: VendorRetailerDetailPhase.ready, detail: value),
        );
        await _loadShops(relationshipId, token);

      case VendorRetailerReadFailure<VendorRetailerDetail?>(
        :final Failure failure,
      ):
        emit(
          state.copyWith(
            phase: VendorRetailerDetailPhase.failed,
            failure: failure,
          ),
        );
    }
  }

  Future<void> _loadShops(String relationshipId, int token) async {
    emit(
      state.copyWith(
        shopsPhase: VendorRetailerShopsPhase.loading,
        clearShopsFailure: true,
      ),
    );

    final VendorRetailerResult<List<VendorRetailerShop>> result =
        await _repository.retailerShops(relationshipId);

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case VendorRetailerReadSuccess<List<VendorRetailerShop>>(
        :final List<VendorRetailerShop> value,
      ):
        emit(
          state.copyWith(
            shopsPhase: VendorRetailerShopsPhase.ready,
            shops: value,
            clearShopsFailure: true,
          ),
        );

      case VendorRetailerReadFailure<List<VendorRetailerShop>>(
        :final Failure failure,
      ):
        emit(
          state.copyWith(
            shopsPhase: VendorRetailerShopsPhase.failed,
            shopsFailure: failure,
          ),
        );
    }
  }
}
