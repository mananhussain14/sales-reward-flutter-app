import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/retailer_read_problem.dart';
import '../../../domain/entities/retailer_assignable_shop.dart';
import '../../../domain/entities/retailer_staff_invitation_outcome.dart';
import '../../../domain/entities/retailer_staff_invitation_request.dart';
import '../../../domain/entities/retailer_staff_invitation_role.dart';
import '../../../domain/repositories/retailer_staff_invitation_repository.dart';

part 'retailer_invite_staff_state.dart';

/// Re-reads the canonical invitation history and reports whether it landed.
///
/// A function rather than a reference to the staff cubit so this cubit owns no
/// other cubit, and so a test can drive "the send succeeded but the history did
/// not reload" without standing up a second bloc.
typedef RetailerInvitationHistoryReread = Future<bool> Function();

/// The Owner's Invite Staff form.
///
/// Backed by `list_retailer_staff_assignable_shops()` for the shop picker and by
/// the shared `send-retailer-staff-invitation` Edge Function for the send. The
/// read takes zero arguments; the send takes exactly five fields and no
/// identity of any kind.
///
/// ## Presentation scope, never authorization
///
/// This cubit is provided only in the Retailer Owner shell, for the same reason
/// the invitation history is read only there: both contracts resolve through the
/// permission a Manager does not hold, so issuing either from a Manager's screen
/// would put a denial notice where nothing is wrong. That is a courtesy. The
/// backend decides — twice, in SQL — on every call, and a hidden form is not a
/// security boundary: a hand-crafted request reaches the function regardless of
/// what any UI rendered.
///
/// ## One send per submission, and no automatic retry anywhere
///
/// [submit] refuses to start while one is in flight, so a double tap cannot
/// produce two invitations. Nothing here re-sends on failure, on timeout, on an
/// unreadable answer, or — most importantly — after a 2xx. Repeating the write
/// re-reserves the invitation, mints a new token and rotates the hash, which
/// kills a link that may already be in the recipient's inbox and delivers a
/// second email. A retry is always a person pressing the button again.
///
/// ## Why an unresolved answer empties the form
///
/// `DELIVERY_ACCEPTED_STATUS_UNCONFIRMED`, a timeout, an unreadable body and an
/// unexpected fault all mean the same thing: an email may already be in
/// somebody's inbox and this build cannot confirm it. The project's existing
/// convention for that state — the unconfirmed product create — is to remove the
/// submit affordance rather than re-arm it, because the one action that must not
/// happen next is another write.
///
/// Emptying the form is that convention applied here: an empty form cannot be
/// resubmitted, the notice says plainly that the status is unconfirmed, and the
/// canonical invitation history is re-read so the person can see what actually
/// exists. A **definite** failure does the opposite and keeps every value, so a
/// deliberate retry costs no retyping.
///
/// ## The history is re-read, never assembled
///
/// The send's response carries no invitation record, so nothing is appended
/// locally. [RetailerInvitationHistoryReread] re-reads
/// `list_retailer_staff_invitations()`, and a reread that fails is reported as
/// exactly that — the invitation was still sent, and the send is never restated
/// as a failure because the read beside it did not land.
final class RetailerInviteStaffCubit extends Cubit<RetailerInviteStaffState> {
  RetailerInviteStaffCubit(
    this._repository, {
    required RetailerInvitationHistoryReread rereadHistory,
  }) : _rereadHistory = rereadHistory,
       super(const RetailerInviteStaffState());

  final RetailerStaffInvitationRepository _repository;
  final RetailerInvitationHistoryReread _rereadHistory;

  /// Discriminates the answers this cubit is waiting for.
  ///
  /// One token covers the shop read, the send and the history reread together: a
  /// session change invalidates everything at once, and there is no case in
  /// which a previous identity's answer should be accepted for one of them while
  /// being dropped for another.
  int _token = 0;

  /// Exposed for the isolation tests.
  int get requestToken => _token;

  // -- typing ---------------------------------------------------------------

  /// Records a keystroke and clears that control's message.
  ///
  /// The message is cleared as soon as the value changes rather than on the next
  /// submission, so a corrected field stops looking wrong while it is being
  /// corrected.
  void firstNameChanged(String value) =>
      _valueChanged(RetailerStaffInvitationField.firstName, firstName: value);

  void lastNameChanged(String value) =>
      _valueChanged(RetailerStaffInvitationField.lastName, lastName: value);

  void emailChanged(String value) =>
      _valueChanged(RetailerStaffInvitationField.email, email: value);

  void _valueChanged(
    RetailerStaffInvitationField field, {
    String? firstName,
    String? lastName,
    String? email,
  }) {
    if (state.isSubmitting) {
      return;
    }
    emit(
      state.copyWith(
        firstName: firstName,
        lastName: lastName,
        email: email,
        fieldProblems: _without(field),
        // A stale success or failure notice above a form being retyped would
        // describe a submission that is no longer the one on screen.
        clearNotice: true,
        historyRereadFailed: false,
      ),
    );
  }

  Map<RetailerStaffInvitationField, RetailerStaffInvitationProblem> _without(
    RetailerStaffInvitationField field,
  ) {
    if (!state.fieldProblems.containsKey(field)) {
      return state.fieldProblems;
    }
    final Map<RetailerStaffInvitationField, RetailerStaffInvitationProblem>
    next = Map<RetailerStaffInvitationField, RetailerStaffInvitationProblem>.of(
      state.fieldProblems,
    )..remove(field);
    return Map<
      RetailerStaffInvitationField,
      RetailerStaffInvitationProblem
    >.unmodifiable(next);
  }

  // -- role and shops -------------------------------------------------------

  /// Chooses the role, and loads the shop options the first time Sales Staff is
  /// chosen.
  ///
  /// A **successful** option list survives every later switch: it belongs to the
  /// Retailer rather than to the role, so re-reading it on each toggle would be
  /// a request whose answer cannot have changed. A read that *failed* is retried
  /// on the next switch back, because that answer can change.
  void roleChanged(RetailerStaffInvitationRole role) {
    if (state.isSubmitting || state.role == role) {
      return;
    }

    emit(
      state.copyWith(
        role: role,
        // The role's own message and the shop message both go: choosing a role
        // is what decides whether a shop selection is required at all, so a
        // "select at least one shop" left over from the other role would be
        // describing a rule that no longer applies.
        fieldProblems: _withoutAll(<RetailerStaffInvitationField>{
          RetailerStaffInvitationField.role,
          RetailerStaffInvitationField.shops,
        }),
        clearNotice: true,
        historyRereadFailed: false,
      ),
    );

    if (role.carriesShops &&
        state.shopsPhase != RetailerInviteShopsPhase.ready) {
      loadAssignableShops();
    }
  }

  Map<RetailerStaffInvitationField, RetailerStaffInvitationProblem> _withoutAll(
    Set<RetailerStaffInvitationField> fields,
  ) {
    final Map<RetailerStaffInvitationField, RetailerStaffInvitationProblem>
    next =
        Map<RetailerStaffInvitationField, RetailerStaffInvitationProblem>.of(
          state.fieldProblems,
        )..removeWhere(
          (RetailerStaffInvitationField field, _) => fields.contains(field),
        );
    return Map<
      RetailerStaffInvitationField,
      RetailerStaffInvitationProblem
    >.unmodifiable(next);
  }

  /// Ticks or unticks one option.
  ///
  /// Keyed on the id the backend returned. A shop's **name** and its **position
  /// in the list** are never used to identify it: two shops may legitimately
  /// share a name, and a position is a property of one response rather than of a
  /// shop.
  void shopSelectionToggled(String shopId) {
    if (state.isSubmitting) {
      return;
    }
    final Set<String> next = Set<String>.of(state.selectedShopIds);
    if (!next.remove(shopId)) {
      next.add(shopId);
    }
    emit(
      state.copyWith(
        selectedShopIds: Set<String>.unmodifiable(next),
        fieldProblems: _without(RetailerStaffInvitationField.shops),
        clearNotice: true,
        historyRereadFailed: false,
      ),
    );
  }

  /// Reads `list_retailer_staff_assignable_shops()`.
  ///
  /// Zero arguments. No Retailer organization id is sent, because the deployed
  /// function has no parameter for one and derives the Retailer from
  /// `auth.uid()`.
  Future<void> loadAssignableShops() async {
    if (state.isShopsLoading) {
      return;
    }

    final int token = ++_token;
    emit(
      state.copyWith(
        shopsPhase: RetailerInviteShopsPhase.loading,
        clearShopsProblem: true,
      ),
    );

    final RetailerAssignableShopsResult result = await _repository
        .assignableShops();

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case RetailerAssignableShopsLoaded(
        :final List<RetailerAssignableShop> shops,
      ):
        final Set<String> available = shops
            .map((RetailerAssignableShop shop) => shop.id)
            .toSet();
        emit(
          state.copyWith(
            shopsPhase: RetailerInviteShopsPhase.ready,
            shops: shops,
            // A tick for a shop this response no longer offers is dropped
            // rather than carried: it would be un-untickable, invisible, and
            // still submitted.
            selectedShopIds: Set<String>.unmodifiable(
              state.selectedShopIds.where(available.contains).toSet(),
            ),
            clearShopsProblem: true,
          ),
        );
      case RetailerAssignableShopsFailed(:final RetailerReadProblem problem):
        emit(
          state.copyWith(
            shopsPhase: RetailerInviteShopsPhase.failed,
            shopsProblem: problem,
          ),
        );
    }
  }

  // -- submission -----------------------------------------------------------

  /// Validates, sends once, and re-reads the canonical history when the answer
  /// warrants it.
  Future<void> submit() async {
    // The whole double-submit guard. The button is disabled too, but a disabled
    // button is a courtesy and this is the rule: a queued second tap, a rebuild
    // racing a rebuild, or a keyboard "go" arriving beside a press all land
    // here.
    if (state.isSubmitting) {
      return;
    }

    final RetailerStaffInvitationInput input =
        RetailerStaffInvitationRequest.validated(
          firstName: state.firstName,
          lastName: state.lastName,
          email: state.email,
          role: state.role,
          // Manager submits none, and a Sales Staff selection is already
          // intersected with what the backend offered.
          shopIds: state.submittableShopIds,
        );

    if (input case RetailerStaffInvitationInvalid(
      :final Map<RetailerStaffInvitationField, RetailerStaffInvitationProblem>
      problems,
    )) {
      // Nothing left the device.
      emit(
        state.copyWith(
          fieldProblems: problems,
          notice: RetailerInviteStaffNotice.checkTheForm,
          historyRereadFailed: false,
        ),
      );
      return;
    }

    final RetailerStaffInvitationRequest request =
        (input as RetailerStaffInvitationValid).request;

    final int token = ++_token;
    emit(
      state.copyWith(
        isSubmitting: true,
        fieldProblems:
            const <
              RetailerStaffInvitationField,
              RetailerStaffInvitationProblem
            >{},
        clearNotice: true,
        historyRereadFailed: false,
      ),
    );

    final RetailerStaffInvitationSendResult result = await _repository.send(
      request,
    );

    // A result for a session, or a submission, that is no longer the current one
    // is dropped on arrival. It must not clear a form the next person is typing
    // into, and it must not put the previous identity's success on their screen.
    if (isClosed || token != _token) {
      return;
    }

    final (
      RetailerInviteStaffNotice notice,
      bool rereadHistory,
    ) = switch (result) {
      RetailerStaffInvitationAnswered(
        :final RetailerStaffInvitationOutcome outcome,
        :final RetailerStaffInvitationCode code,
      ) =>
        (
          _noticeFor(outcome, code),
          // Re-read whenever the message may have reached the provider — which
          // includes a recorded delivery failure, because that failure is
          // itself a row on the history the Owner is looking at.
          outcome.reachedProvider,
        ),
      RetailerStaffInvitationUnanswered(
        :final RetailerStaffInvitationTransportProblem problem,
      ) =>
        (
          _noticeForTransport(problem),
          // A timeout, an unreadable answer and an unexpected fault all leave
          // the outcome unknown, and the history is the only authority on it. A
          // request that never left does not.
          problem != RetailerStaffInvitationTransportProblem.network &&
              problem != RetailerStaffInvitationTransportProblem.signedOut,
        ),
    };

    final bool resetForm = notice.isSuccess || notice.isUnresolved;

    emit(
      resetForm
          // A fresh state rather than a copy: it is the only way to unset the
          // role, and it guarantees no typed value, tick or message survives.
          // The options and the notice are carried across deliberately —
          // re-reading the estate would be a request whose answer cannot have
          // changed, and losing the notice would leave a blank form with no word
          // of what just happened.
          ? RetailerInviteStaffState(
              shopsPhase: state.shopsPhase,
              shops: state.shops,
              shopsProblem: state.shopsProblem,
              notice: notice,
              formRevision: state.formRevision + 1,
            )
          : state.copyWith(isSubmitting: false, notice: notice),
    );

    if (!rereadHistory) {
      return;
    }

    final bool reread = await _rereadHistory();

    if (isClosed || token != _token || reread) {
      return;
    }

    // The send stands exactly as reported above. Only the history beside it is
    // stale, and the action offered for that is a read.
    emit(state.copyWith(historyRereadFailed: true));
  }

  RetailerInviteStaffNotice _noticeFor(
    RetailerStaffInvitationOutcome outcome,
    RetailerStaffInvitationCode code,
  ) {
    // The outcome is read first and decides the group. The code only chooses
    // between sentences within it, so a code this build has never seen still
    // produces copy that is true about the email.
    return switch (outcome) {
      RetailerStaffInvitationOutcome.sent => RetailerInviteStaffNotice.sent,
      RetailerStaffInvitationOutcome.resent => RetailerInviteStaffNotice.resent,
      RetailerStaffInvitationOutcome.deliveryAcceptedStatusUnconfirmed =>
        RetailerInviteStaffNotice.deliveryUnconfirmed,
      RetailerStaffInvitationOutcome.deliveryFailed =>
        RetailerInviteStaffNotice.deliveryFailed,
      RetailerStaffInvitationOutcome.notSent => switch (code) {
        RetailerStaffInvitationCode.invalidRoleShopCombination =>
          RetailerInviteStaffNotice.invalidRoleShopCombination,
        RetailerStaffInvitationCode.authRequired =>
          RetailerInviteStaffNotice.signedOut,
        RetailerStaffInvitationCode.accessDenied =>
          RetailerInviteStaffNotice.accessDenied,
        RetailerStaffInvitationCode.invitationConflict =>
          RetailerInviteStaffNotice.invitationConflict,
        RetailerStaffInvitationCode.retailerInactive =>
          RetailerInviteStaffNotice.retailerInactive,
        RetailerStaffInvitationCode.featureDisabled =>
          RetailerInviteStaffNotice.featureDisabled,
        RetailerStaffInvitationCode.notConfigured =>
          RetailerInviteStaffNotice.notConfigured,
        RetailerStaffInvitationCode.methodNotAllowed ||
        RetailerStaffInvitationCode.internalError =>
          RetailerInviteStaffNotice.serviceFault,
        // `INVALID_REQUEST` and every NOT_SENT token this build does not know.
        // The generic case for the recognised outcome, which is what the
        // contract requires of a client meeting a newer code.
        _ => RetailerInviteStaffNotice.invalidRequest,
      },
    };
  }

  RetailerInviteStaffNotice _noticeForTransport(
    RetailerStaffInvitationTransportProblem problem,
  ) => switch (problem) {
    RetailerStaffInvitationTransportProblem.network =>
      RetailerInviteStaffNotice.network,
    RetailerStaffInvitationTransportProblem.timeout =>
      RetailerInviteStaffNotice.timedOut,
    RetailerStaffInvitationTransportProblem.signedOut =>
      RetailerInviteStaffNotice.signedOut,
    RetailerStaffInvitationTransportProblem.malformed =>
      RetailerInviteStaffNotice.unreadableAnswer,
    RetailerStaffInvitationTransportProblem.unexpected =>
      RetailerInviteStaffNotice.unexpected,
  };

  /// Drops every typed value, the chosen role, the ticked shops, the options,
  /// the submission result, every message and the in-flight token.
  ///
  /// Called when the signed-in person or the resolved Retailer changes. What it
  /// protects is real: a colleague's name and personal email address, and the
  /// shops of one Retailer's estate, neither of which belongs on the next
  /// session's screen for even an instant.
  ///
  /// Advancing the token first means a shop read, a send, or a history reread
  /// already in flight for the previous identity is dropped on arrival rather
  /// than refilling a form that has just been emptied — including a send whose
  /// answer was already on its way when the session ended.
  void clear() {
    _token++;
    // The revision keeps climbing across a clear, and that is load-bearing
    // rather than tidy: the text controllers live in the widget and follow the
    // cubit only when it *changes* the revision. Emitting the default state
    // with revision 0 would leave the boxes holding the previous session's
    // colleague's name and address — cleared in state, still on screen.
    emit(RetailerInviteStaffState(formRevision: state.formRevision + 1));
  }
}
