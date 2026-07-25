import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/failure.dart';
import '../../../domain/entities/vendor_retailer_detail.dart';
import '../../../domain/entities/vendor_retailer_shop.dart';
import '../../../domain/repositories/vendor_retailer_repository.dart';
import '../../../domain/repositories/vendor_retailer_result.dart';

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

  /// Drops the open Retailer and its shops.
  ///
  /// Called when the signed-in person changes, so one Vendor's Retailer can
  /// never remain on screen for the next. The token is advanced first, so an
  /// answer already in flight for the previous person cannot repopulate the
  /// state after it has been emptied.
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
