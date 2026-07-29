import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/failure.dart';
import '../../../domain/entities/vendor_retailer_lifecycle_action.dart';
import '../../../domain/entities/vendor_retailer_lifecycle_status.dart';
import '../../../domain/repositories/vendor_retailer_lifecycle_repository.dart';
import '../../../domain/repositories/vendor_retailer_write_result.dart';
import 'vendor_retailer_lifecycle_notice.dart';

part 'vendor_retailer_lifecycle_state.dart';

/// Drives one `set_vendor_retailer_status` call over one already-loaded
/// Retailer.
///
/// ## Which change is offered comes from the Retailer, not from this cubit
///
/// [apply] takes an already-derived [VendorRetailerLifecycleAction], produced by
/// [VendorRetailerLifecycleAction.forPair] from the two statuses the canonical
/// detail read returned. This cubit never inspects a status, never compares one,
/// and never decides a direction — so there is no second place for the
/// transition rule to live, and no path by which a button's *text* could
/// determine what is sent.
///
/// ## Nothing here is optimistic
///
/// The visible status is never flipped ahead of the backend. It changes when —
/// and only when — a fresh `get_vendor_retailer_detail` says so, which is why a
/// failure leaves the previous badges on screen untouched rather than having to
/// undo a guess.
///
/// ## Nothing here is ever retried
///
/// Not automatically, and not by a re-armed button after
/// [VendorRetailerWriteUnconfirmed]. The write committed in that case, and there
/// is nothing left to retry; the canonical re-read is what then says which
/// status the pair holds. A *failure* is different — every deployed refusal
/// raises and rolls back — so the action is offered again there.
///
/// ## Deactivation is not deletion, and this cubit changes nothing else
///
/// The RPC moves two status columns and nothing else. Memberships, roles, Shops,
/// live and retired Shop assignments, product assignments, receipts, both
/// invitation tables, profiles and the audit history are all preserved, which is
/// why reactivation restores access without recreating anything. Nothing here
/// writes, removes or recounts any of them.
final class VendorRetailerLifecycleCubit
    extends Cubit<VendorRetailerLifecycleState> {
  VendorRetailerLifecycleCubit(this._repository, {this.onRetailerWritten})
    : super(const VendorRetailerLifecycleState());

  final VendorRetailerLifecycleRepository _repository;

  /// Called once when a lifecycle change settles as something the Retailer
  /// screens must re-read: the shell wires it to the detail cubit's canonical
  /// refresh and to the directory's.
  ///
  /// Called for a **committed** outcome only — a success or an unconfirmed
  /// success. A failure changed nothing, so there is nothing to re-read.
  final void Function(VendorRetailerLifecycleNotice notice)? onRetailerWritten;

  /// Discriminates the answer this cubit is currently waiting for.
  ///
  /// Advanced by [clear], so a request already in flight for the previous
  /// signed-in person is dropped on arrival rather than reporting into the new
  /// session — which is what stops one Vendor's lifecycle decision leaving a
  /// "Retailer deactivated" notice over somebody else's Retailer.
  int _token = 0;

  /// Applies [action] to [relationshipId].
  ///
  /// Called only after the confirmation dialog was accepted — the dialog is the
  /// screen's job, and this method deliberately knows nothing about it, so a
  /// test can exercise the write without a widget *and* a screen cannot skip the
  /// confirmation by calling something cheaper.
  ///
  /// The first line is the duplicate-submission guard: a second call while one
  /// is in flight returns immediately, without a second RPC.
  Future<void> apply(
    String relationshipId,
    VendorRetailerLifecycleAction action,
  ) async {
    if (state.isBusy) {
      return;
    }

    final int token = ++_token;
    emit(
      VendorRetailerLifecycleState(
        relationshipId: relationshipId,
        pending: action,
        phase: VendorRetailerLifecyclePhase.submitting,
      ),
    );

    // Exactly one call. The requested status comes from the action's own table
    // — the single place in this application a value destined for `p_status` is
    // produced.
    final VendorRetailerWriteResult result = await _repository
        .setRetailerStatus(
          relationshipId: relationshipId,
          status: action.requestedStatus,
        );

    if (isClosed || token != _token) {
      // A session change, or a request this one was superseded by. Dropping the
      // answer here is what stops one Vendor's lifecycle change reporting into
      // another Vendor's session.
      return;
    }

    switch (result) {
      case VendorRetailerWriteSuccess(
        :final VendorRetailerLifecycleStatus confirmedStatus,
        :final bool statusChanged,
      ):
        // The notice is chosen from the status the DATABASE confirmed, never
        // from the one that was requested, and it distinguishes a real change
        // from an idempotent no-op because those mean different things to an
        // administrator.
        final VendorRetailerLifecycleNotice notice = switch ((
          confirmedStatus,
          statusChanged,
        )) {
          (VendorRetailerLifecycleStatus.suspended, true) =>
            VendorRetailerLifecycleNotice.deactivated,
          (VendorRetailerLifecycleStatus.suspended, false) =>
            VendorRetailerLifecycleNotice.alreadyInactive,
          (VendorRetailerLifecycleStatus.active, true) =>
            VendorRetailerLifecycleNotice.reactivated,
          (VendorRetailerLifecycleStatus.active, false) =>
            VendorRetailerLifecycleNotice.alreadyActive,
        };
        emit(state.copyWith(phase: VendorRetailerLifecyclePhase.applied));
        onRetailerWritten?.call(notice);

      case VendorRetailerWriteUnconfirmed():
        // No error, so the transaction committed — but the body could not be
        // trusted. This is never reported as a failure and never retried; the
        // canonical re-read is what then says which status the pair holds.
        emit(state.copyWith(phase: VendorRetailerLifecyclePhase.applied));
        onRetailerWritten?.call(VendorRetailerLifecycleNotice.unconfirmed);

      case VendorRetailerWriteFailure(:final Failure failure):
        // Nothing was written, so the statuses already on screen are still
        // correct and are left exactly as they are. The action is offered again.
        emit(
          state.copyWith(
            phase: VendorRetailerLifecyclePhase.failed,
            failure: failure,
          ),
        );
    }
  }

  /// Dismisses a failure, returning the action to its resting state.
  void dismissFailure() {
    if (state.phase != VendorRetailerLifecyclePhase.failed) {
      return;
    }
    emit(const VendorRetailerLifecycleState());
  }

  /// Drops any pending decision, progress, result and error.
  ///
  /// Called when the signed-in person changes. A pending lifecycle decision
  /// names a Retailer in the previous Vendor's directory; advancing the token
  /// first means a request already in flight for them cannot report into the new
  /// session, and certainly cannot leave a "Retailer deactivated" notice over
  /// somebody else's Retailer.
  void clear() {
    _token++;
    emit(const VendorRetailerLifecycleState());
  }
}
