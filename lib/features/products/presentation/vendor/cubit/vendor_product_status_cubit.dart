import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/failure.dart';
import '../../../domain/entities/vendor_product_status_change.dart';
import '../../../domain/repositories/vendor_product_repository.dart';
import '../../../domain/repositories/vendor_product_write_result.dart';
import 'vendor_product_write_notice.dart';

part 'vendor_product_status_state.dart';

/// Drives one `set_vendor_product_status` call over one already-loaded product.
///
/// ## It is a separate action, because it is a separate operation
///
/// `update_vendor_product` never writes `status` and this function never writes
/// the display fields, so the two can neither substitute for nor clobber one
/// another — they take `FOR UPDATE` on the same row and serialize. Keeping them
/// separate on screen is not a layout preference: a status control inside the edit
/// form would suggest that correcting a name and withdrawing a product are one
/// decision, which is exactly what the contract refuses to let them be.
///
/// ## Which change is offered comes from the product, not from this cubit
///
/// [VendorProductStatusChange.forCurrent] reads the status the canonical row
/// returned. An `ACTIVE` product offers Deactivate, an `INACTIVE` one offers
/// Activate, and a status token this build does not recognise offers **neither** —
/// guessing the opposite of an unfamiliar status would be inventing a transition.
///
/// ## Nothing here is optimistic
///
/// The visible status is never flipped ahead of the backend. It changes when — and
/// only when — a fresh `get_vendor_product_detail` says so, which is why a failure
/// leaves the previous status on screen untouched rather than having to undo a
/// guess. A same-status request is an idempotent no-op in SQL, so a double
/// confirmation cannot record two decisions even if one got through.
///
/// ## Deactivation is not deletion, and this cubit changes no assignment
///
/// The row, its `created_at` and every one of its assignment rows survive a
/// deactivation untouched, down to their `updated_at`. Nothing here writes,
/// removes, re-reads or recounts an assignment: the counts on screen come from the
/// re-read product row, which is the same statement that produced them before.
final class VendorProductStatusCubit extends Cubit<VendorProductStatusState> {
  VendorProductStatusCubit(this._repository, {this.onProductWritten})
    : super(const VendorProductStatusState());

  final VendorProductRepository _repository;

  /// Called once when a status change settles as something the product screens
  /// must re-read: the shell wires it to the detail cubit's canonical refresh and
  /// to the catalogue's.
  final void Function(VendorProductWriteNotice notice)? onProductWritten;

  int _token = 0;

  /// Applies [change] to [productId].
  ///
  /// Called only after the confirmation dialog was accepted — the dialog is the
  /// screen's job, and this method deliberately knows nothing about it, so a test
  /// can exercise the write without a widget and a screen cannot skip the
  /// confirmation by calling something cheaper.
  ///
  /// The first line is the duplicate-confirmation guard: a second call while one is
  /// in flight returns immediately.
  Future<void> apply(String productId, VendorProductStatusChange change) async {
    if (state.isBusy) {
      return;
    }

    final int token = ++_token;
    emit(
      VendorProductStatusState(
        productId: productId,
        pending: change,
        phase: VendorProductStatusPhase.submitting,
      ),
    );

    final VendorProductWriteResult<void> result = await _repository
        .setProductStatus(productId, change);

    if (isClosed || token != _token) {
      // A session change, or a request this one was superseded by. Dropping the
      // answer here is what stops one Vendor's status change from reporting into
      // another Vendor's session.
      return;
    }

    switch (result) {
      case VendorProductWriteSuccess<void>():
        emit(state.copyWith(phase: VendorProductStatusPhase.applied));
        onProductWritten?.call(VendorProductWriteNotice.statusChanged);

      case VendorProductWriteUnconfirmed<void>():
        // 2xx with a body this build cannot read. The row and its audit row are
        // committed, so this is never reported as a failure; the canonical re-read
        // is what then says which status the product holds.
        emit(state.copyWith(phase: VendorProductStatusPhase.applied));
        onProductWritten?.call(VendorProductWriteNotice.statusUnconfirmed);

      case VendorProductWriteFailure<void>(:final Failure failure):
        // Nothing was written, so the status already on screen is still correct and
        // is left exactly as it is. The action is offered again.
        emit(
          state.copyWith(
            phase: VendorProductStatusPhase.failed,
            failure: failure,
          ),
        );
    }
  }

  /// Dismisses a failure, returning the action to its resting state.
  void dismissFailure() {
    if (state.phase != VendorProductStatusPhase.failed) {
      return;
    }
    emit(const VendorProductStatusState());
  }

  /// Drops any pending confirmation, progress, result and error.
  ///
  /// Called when the signed-in person changes. A pending status decision names a
  /// product in the previous Vendor's catalogue; advancing the token first means a
  /// request already in flight for them cannot report into the new session, and can
  /// certainly not leave a "Deactivated" notice over somebody else's product.
  void clear() {
    _token++;
    emit(const VendorProductStatusState());
  }
}
