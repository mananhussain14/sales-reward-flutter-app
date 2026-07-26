import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/failure.dart';
import '../../../../retailers/domain/entities/vendor_retailer_summary.dart';
import '../../../../retailers/domain/repositories/vendor_retailer_repository.dart';
import '../../../../retailers/domain/repositories/vendor_retailer_result.dart';
import '../../../domain/entities/vendor_product_assigned_retailer.dart';
import '../../../domain/entities/vendor_product_assignment_action.dart';
import '../../../domain/entities/vendor_product_assignment_candidate.dart';
import '../../../domain/entities/vendor_product_assignment_request.dart';
import '../../../domain/repositories/vendor_product_repository.dart';
import '../../../domain/repositories/vendor_product_write_result.dart';
import 'vendor_product_write_notice.dart';

part 'vendor_product_assignment_state.dart';

/// Drives the two Product-to-Retailer assignment writes over one already-loaded
/// Product, and composes the choices they may address.
///
/// ## It is a separate cubit, because it is a separate entitlement
///
/// `assign_vendor_product_to_retailer` and
/// `unassign_vendor_product_from_retailer` are gated on
/// **`PRODUCT_RETAILER_ASSIGN`**, which the backend proved — by removing each
/// seeded mapping in turn — is distinct from `PRODUCTS_MANAGE` in *both*
/// directions: a caller holding only `PRODUCTS_MANAGE` is refused both of these,
/// and a caller holding only `PRODUCT_RETAILER_ASSIGN` is refused
/// `set_vendor_product_status`. Folding assignment into the status cubit would
/// therefore be modelling two entitlements as one, and a screen that inferred
/// "may edit this Product, therefore may assign it" would be asserting something
/// the database contradicts.
///
/// This cubit names, sends, inspects and displays neither code. It calls the
/// function and handles the refusal.
///
/// ## Where the candidate Retailers come from
///
/// Two already-deployed reads, and **no third call**:
///
/// * `list_vendor_retailers()`, through the shipped
///   [VendorRetailerRepository] — the same `vendor_retailers` set the write
///   reaches a Retailer through, scoped to the derived Vendor in SQL, carrying
///   both statuses the assign gate consults;
/// * `list_vendor_product_assigned_retailers(p_product_id)`, whose rows the
///   Product detail screen already holds and passes in — the only thing that can
///   tell "never assigned" apart from "assigned and withdrawn".
///
/// No table is read, no eligibility probe is issued per Retailer, and nothing is
/// inferred from the *absence* of an assignment row alone: a Retailer with no
/// row is only offered when the directory also says its organization and this
/// Vendor's relationship with it are both active.
///
/// The directory is re-read **each time the picker opens**, deliberately. The
/// shell loads it once on entry, and eligibility is exactly the thing that goes
/// stale: a relationship suspended ten minutes ago must not still look
/// assignable. It is still only a hint — see below.
///
/// ## Nothing here is authorization, and nothing here is optimistic
///
/// [VendorProductAssignmentCandidateState] is a presentation hint computed from
/// what was last read. The backend re-decides eligibility inside the write,
/// under row locks, and is entitled to refuse a selection this client called
/// assignable — which is not a defect to engineer around but the contract
/// working: the database is the authority and the client is a convenience.
///
/// No assignment row is inserted, removed or re-statused locally on success.
/// Both RPCs return `void`, so what a pairing now looks like comes from
/// re-reading `get_vendor_product_detail` and
/// `list_vendor_product_assigned_retailers`, and from nowhere else. That re-read
/// is [onAssignmentWritten]'s job, which keeps it in one place rather than
/// growing a copy here.
///
/// ## Duplicate submission
///
/// [apply] refuses a second call while one is in flight, and the controls
/// disable themselves for the pairing being written. Even a request that somehow
/// got through twice could not record two decisions: assigning an already-active
/// pairing and withdrawing an already-inactive one are both silent backend
/// no-ops that write no row and no audit entry, and the unique index makes a
/// second history row structurally impossible.
final class VendorProductAssignmentCubit
    extends Cubit<VendorProductAssignmentState> {
  VendorProductAssignmentCubit(
    this._products,
    this._retailers, {
    this.onAssignmentWritten,
  }) : super(const VendorProductAssignmentState());

  final VendorProductRepository _products;
  final VendorRetailerRepository _retailers;

  /// Called once when an assignment write settles as something the Product
  /// screens must re-read: the shell wires it to the detail cubit's canonical
  /// refresh — which re-reads the history **and** the counts — and to the
  /// catalogue's, whose `active_assignment_count` moved too.
  final void Function(VendorProductWriteNotice notice)? onAssignmentWritten;

  /// Discriminates the answer this cubit is currently waiting for.
  ///
  /// One token for both the candidate read and the writes, because both must be
  /// invalidated by the same events: a session change, and opening the picker
  /// for a different Product. Every request captures the token it started under
  /// and compares it before emitting, so an answer that lands after [clear] is
  /// dropped rather than reported into whoever is signed in now.
  int _token = 0;

  /// Loads the Retailers this Product could be assigned to.
  ///
  /// [assignments] is the canonical assignment history the detail screen already
  /// holds — passed in rather than re-read here, so the picker cannot show a
  /// different history from the list underneath it.
  ///
  /// A second call while one is in flight is a no-op, which is the
  /// duplicate-tap guard for the Assign button.
  Future<void> loadCandidates({
    required String productId,
    required List<VendorProductAssignedRetailer> assignments,
  }) async {
    if (state.isLoadingCandidates) {
      return;
    }

    final int token = ++_token;

    // A fresh candidate state, so nothing from a previously open picker — a
    // search term, an old eligibility verdict, a dismissed failure — survives
    // into this one. Any write result is cleared with it: an acknowledgement
    // belongs beside the history it changed, not on top of a new list.
    emit(
      VendorProductAssignmentState(
        productId: productId,
        candidatesPhase: VendorProductAssignmentCandidatesPhase.loading,
      ),
    );

    final VendorRetailerResult<List<VendorRetailerSummary>> result =
        await _retailers.retailers();

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case VendorRetailerReadSuccess<List<VendorRetailerSummary>>(
        :final List<VendorRetailerSummary> value,
      ):
        emit(
          state.copyWith(
            candidatesPhase: VendorProductAssignmentCandidatesPhase.ready,
            candidates: VendorProductAssignmentCandidate.compose(
              retailers: value,
              assignments: assignments,
            ),
          ),
        );

      case VendorRetailerReadFailure<List<VendorRetailerSummary>>(
        :final Failure failure,
      ):
        // An empty candidate list is never produced from a failure: "you manage
        // no Retailers" and "we could not read your Retailers" are opposite
        // claims, and offering the first when the second happened would invite
        // somebody to conclude their directory had been emptied.
        emit(
          state.copyWith(
            candidatesPhase: VendorProductAssignmentCandidatesPhase.failed,
            candidatesFailure: failure,
          ),
        );
    }
  }

  /// Narrows the loaded candidates by Retailer name, case-insensitively.
  ///
  /// Local, over the complete trusted answer: `list_vendor_retailers()` is
  /// unpaginated and has no search parameter, so filtering the loaded rows is
  /// filtering everything there is, and sending a term would mean inventing an
  /// argument the deployed function does not have.
  void searchCandidates(String term) => emit(state.copyWith(searchTerm: term));

  /// Drops the candidate list, the search term and any candidate failure.
  ///
  /// Called when the picker closes. The list is not kept as a cache on purpose:
  /// eligibility is the thing that goes stale, and re-reading on the next open
  /// costs one call and cannot show a relationship that was suspended in
  /// between.
  ///
  /// A write result is deliberately **preserved**: the acknowledgement belongs
  /// to the history below, which is still on screen after the picker closes.
  void closeCandidates() {
    if (state.candidatesPhase ==
            VendorProductAssignmentCandidatesPhase.initial &&
        state.searchTerm.isEmpty) {
      return;
    }
    // The token advances, so a candidate read still in flight cannot repopulate
    // a picker that is no longer open.
    _token++;
    emit(state.withoutCandidates());
  }

  /// Applies one assignment transition to one pairing.
  ///
  /// Called only after the confirmation dialog was accepted — the dialog is the
  /// screen's job, and this method deliberately knows nothing about it, so a
  /// test can exercise the write without a widget and a screen cannot skip the
  /// confirmation by calling something cheaper.
  ///
  /// The first line is the duplicate-confirmation guard: a second call while one
  /// is in flight returns immediately, whichever pairing or action it names.
  ///
  /// [action] chooses the **function**, never a parameter:
  /// [VendorProductAssignmentAction.assign] and
  /// [VendorProductAssignmentAction.reactivate] both reach
  /// `assign_vendor_product_to_retailer`, because creating and reactivating are
  /// one operation in SQL; only the sentence a reader is shown differs.
  Future<void> apply({
    required String productId,
    required String retailerOrganizationId,
    required VendorProductAssignmentAction action,
  }) async {
    if (state.isBusy) {
      return;
    }

    final int token = ++_token;
    final VendorProductAssignmentRequest request =
        VendorProductAssignmentRequest(
          productId: productId,
          retailerOrganizationId: retailerOrganizationId,
        );

    emit(
      state.copyWith(
        productId: productId,
        pendingRetailerOrganizationId: retailerOrganizationId,
        pendingAction: action,
        phase: VendorProductAssignmentPhase.submitting,
        clearFailure: true,
        clearNotice: true,
      ),
    );

    final VendorProductWriteResult<void> result = action.isWithdrawal
        ? await _products.withdrawRetailer(request)
        : await _products.assignRetailer(request);

    if (isClosed || token != _token) {
      // A session change, a different Product, or a request this one was
      // superseded by. Dropping the answer here is what stops one Vendor's
      // assignment from reporting into another Vendor's session — and what stops
      // a stale acknowledgement appearing over a Product it was never about.
      return;
    }

    switch (result) {
      case VendorProductWriteSuccess<void>():
        _settle(_noticeFor(action));

      case VendorProductWriteUnconfirmed<void>():
        // 2xx with a body this build cannot read. The row and its audit row are
        // committed — the functions raise rather than return on every refusal —
        // so this is never reported as a failure and never retried. The
        // canonical re-read is what then says what the pairing looks like.
        _settle(VendorProductWriteNotice.assignmentUnconfirmed);

      case VendorProductWriteFailure<void>(:final Failure failure):
        // Nothing was written: authorization, eligibility, the mutation and the
        // audit insert are one transaction, so a refusal leaves the assignment
        // exactly as it was. The history on screen is still correct and is left
        // untouched, and the action is offered again.
        emit(
          state.copyWith(
            phase: VendorProductAssignmentPhase.failed,
            failure: failure,
          ),
        );
    }
  }

  /// Dismisses a failure, returning the action to its resting state.
  void dismissFailure() {
    if (state.phase != VendorProductAssignmentPhase.failed) {
      return;
    }
    emit(state.withoutResult());
  }

  /// Drops the candidates, the search term, any pending decision, progress,
  /// result and error.
  ///
  /// Called when the signed-in person changes. Everything here is private Vendor
  /// data — the names and trading statuses of the Retailers one Vendor works
  /// with, a search term that is a fragment of one of those names, and a pending
  /// decision about one Vendor's own Product. The token is advanced first, so a
  /// candidate read, an assign or a withdrawal already in flight for the previous
  /// person cannot report into the new session, and certainly cannot leave an
  /// "Assignment withdrawn" notice over somebody else's Product.
  void clear() {
    _token++;
    emit(const VendorProductAssignmentState());
  }

  /// Records the settled write and hands the canonical re-read to the shell.
  ///
  /// The candidate list is dropped with it: it described eligibility *before*
  /// this transition, and a picker reopened afterwards must ask again rather
  /// than offer a stale verdict about the pairing that has just moved.
  void _settle(VendorProductWriteNotice notice) {
    emit(
      state.withoutCandidates().copyWith(
        phase: VendorProductAssignmentPhase.applied,
        notice: notice,
      ),
    );
    onAssignmentWritten?.call(notice);
  }

  static VendorProductWriteNotice _noticeFor(
    VendorProductAssignmentAction action,
  ) => switch (action) {
    VendorProductAssignmentAction.assign => VendorProductWriteNotice.assigned,
    VendorProductAssignmentAction.reactivate =>
      VendorProductWriteNotice.reactivated,
    VendorProductAssignmentAction.withdraw =>
      VendorProductWriteNotice.withdrawn,
  };
}
