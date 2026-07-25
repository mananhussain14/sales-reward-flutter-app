import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/failure.dart';
import '../../../../../core/result/read_result.dart';
import '../../../domain/entities/vendor_user_detail.dart';
import '../../../domain/repositories/vendor_user_repository.dart';

part 'vendor_user_detail_state.dart';

/// One Vendor user, opened from the directory.
///
/// **One call, once:** `get_vendor_user_detail(p_membership_id)`. There is no
/// companion read — roles arrive inside the same row as a `text[]`, so there is
/// no role query, no permission query and nothing to sequence.
///
/// ## Zero rows is one non-leaking state
///
/// An unknown membership id, another Vendor's membership id, a **Retailer-owned**
/// membership id and a malformed one all arrive here as the same `null` and
/// become the same [VendorUserDetailPhase.notFound]. The screen says the user is
/// not available to this account and says nothing about whether they exist — a
/// distinguishable message would confirm that another Vendor's user exists, and
/// by sweeping ids, roughly how many.
///
/// It is also **not** an outage: `notFound` offers no retry, because retrying
/// cannot change the answer.
///
/// ## One instance, provided by the Vendor shell
///
/// The cubit is owned by the shell rather than created per route, for two
/// reasons. It lets the shell's session isolation clear it on a user change — a
/// cubit created below the route would be unreachable from that listener. And
/// [open] is idempotent, so a router refresh or a widget rebuild that re-enters
/// the same membership issues no second RPC.
final class VendorUserDetailCubit extends Cubit<VendorUserDetailState> {
  VendorUserDetailCubit(this._repository)
    : super(const VendorUserDetailState());

  final VendorUserRepository _repository;

  /// Discriminates the answer this cubit is currently waiting for.
  ///
  /// Every read captures the token it started under and compares it before
  /// emitting. Opening a second user while the first is in flight, or clearing
  /// on a session change, therefore cannot be overwritten by the earlier answer
  /// arriving late — the classic stale-response race, closed the same way
  /// `SessionBloc` closes it.
  int _token = 0;

  /// Loads [membershipId], unless it is already loaded or loading.
  ///
  /// Idempotent on purpose: widget rebuilds, router refreshes and a second entry
  /// into the same route must not produce a second request. A *different* id
  /// always starts a fresh load, and so does the same id after [clear].
  Future<void> open(String membershipId) {
    if (state.membershipId == membershipId &&
        state.phase != VendorUserDetailPhase.initial) {
      return Future<void>.value();
    }
    return _load(membershipId);
  }

  /// Re-reads the currently open user.
  ///
  /// Offered only for an operational failure. There is no retry from
  /// [VendorUserDetailPhase.notFound]: the backend already answered, and it will
  /// answer the same way.
  Future<void> retry() {
    final String? membershipId = state.membershipId;
    if (membershipId == null || state.isLoading) {
      return Future<void>.value();
    }
    return _load(membershipId);
  }

  /// Drops the open user.
  ///
  /// Called when the signed-in person changes, so one Vendor's colleague can
  /// never remain on screen for the next. The token is advanced first, so an
  /// answer already in flight for the previous person cannot repopulate the
  /// state after it has been emptied.
  void clear() {
    _token++;
    emit(const VendorUserDetailState());
  }

  Future<void> _load(String membershipId) async {
    final int token = ++_token;

    emit(
      VendorUserDetailState(
        membershipId: membershipId,
        phase: VendorUserDetailPhase.loading,
      ),
    );

    final ReadResult<VendorUserDetail?> result = await _repository.userDetail(
      membershipId,
    );

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case ReadSuccess<VendorUserDetail?>(:final VendorUserDetail? value):
        emit(
          value == null
              // Not addressable by this caller. One state for "no such id",
              // "somebody else's id", "a Retailer's membership id" and
              // "malformed id" alike.
              ? state.copyWith(phase: VendorUserDetailPhase.notFound)
              : state.copyWith(
                  phase: VendorUserDetailPhase.ready,
                  detail: value,
                ),
        );

      case ReadFailure<VendorUserDetail?>(:final Failure failure):
        emit(
          state.copyWith(phase: VendorUserDetailPhase.failed, failure: failure),
        );
    }
  }
}
