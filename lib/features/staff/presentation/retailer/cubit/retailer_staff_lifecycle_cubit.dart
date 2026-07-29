import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/retailer_staff_lifecycle_action.dart';
import '../../../domain/entities/retailer_staff_lifecycle_status.dart';
import '../../../domain/repositories/retailer_staff_lifecycle_repository.dart';

part 'retailer_staff_lifecycle_state.dart';

/// Drives `set_retailer_staff_membership_status` over the roster's rows.
///
/// ## Independent per membership, because the backend is
///
/// The deployed function serializes on the **target row** with `FOR UPDATE`, so
/// two different memberships are two different rows and never contend. Requests
/// for different colleagues therefore proceed independently, each carrying its
/// own generation, and each landing only on the card that asked.
///
/// The only thing refused is a **duplicate request for the same membership**, and
/// that row's control is disabled for exactly as long as the refusal would last.
/// The two facts together give the property that matters:
///
/// > **An enabled control is never silently ignored.**
///
/// An earlier design guarded on "any request in flight" while disabling only the
/// asking row. That combination left every other button visibly enabled and
/// quietly inert — a press that opened a dialog, took a confirmation, and did
/// nothing. It is deliberately not what this cubit does.
///
/// ## Which change is offered comes from the roster, not from this cubit
///
/// [apply] takes an already-derived [RetailerStaffLifecycleAction], produced by
/// [RetailerStaffLifecycleEligibility.actionFor] over the **whole** roster. This
/// cubit never inspects a status, never compares a role, and never decides a
/// direction — so there is no second place for the eligibility rule to live, and
/// no path by which a button's *text* could determine what is sent.
///
/// ## Nothing here is optimistic
///
/// No status is held, patched or emitted. The visible badge comes from the
/// canonical roster and changes when — and only when — a fresh
/// `list_retailer_staff_members()` says so, which is why a refusal leaves the
/// previous badge untouched rather than having to undo a guess.
///
/// ## Nothing here is ever retried
///
/// Not automatically, and not by a re-armed button after
/// [RetailerStaffLifecycleUnconfirmed]. The write committed in that case and
/// there is nothing left to retry.
///
/// ## Deactivation is not deletion, and this cubit changes nothing else
///
/// The RPC moves `status` and `deactivated_at` and nothing else. The profile, the
/// Auth identity, the roles, the live and retired Shop assignments, the receipts,
/// the invitations and the audit history are all preserved, which is why
/// reactivation restores access without recreating anything.
final class RetailerStaffLifecycleCubit
    extends Cubit<RetailerStaffLifecycleState> {
  RetailerStaffLifecycleCubit(this._repository, {required this.rereadRoster})
    : super(const RetailerStaffLifecycleState());

  final RetailerStaffLifecycleRepository _repository;

  /// The canonical re-read, wired by the shell to the cubit that owns the roster
  /// this screen renders.
  ///
  /// The write's response carries a status and a change flag — **never a roster
  /// row** — so no card is ever patched locally. Called for a **committed**
  /// outcome whose membership is still current: a success, a no-op and an
  /// unconfirmed success all re-read; a refusal changed nothing, so there is
  /// nothing to re-read, and a suppressed result re-reads nothing either (see
  /// [rosterChanged]).
  final Future<void> Function() rereadRoster;

  /// One generation per membership.
  ///
  /// Bumped when a request starts, and bumped again — without starting one — by
  /// [rosterChanged] when that membership leaves the roster. Comparing the
  /// generation on arrival is what drops a superseded or invalidated answer.
  final Map<String, int> _generations = <String, int>{};

  /// One generation for the whole cubit, bumped by [clear].
  ///
  /// A session change invalidates **every** in-flight request at once, including
  /// memberships this cubit has never seen a generation for.
  int _epoch = 0;

  /// Exposed for the isolation tests.
  int get epoch => _epoch;

  /// Applies [action] to [membershipId].
  ///
  /// Called only after the confirmation dialog was accepted — the dialog is the
  /// screen's job, and this method deliberately knows nothing about it, so a test
  /// can exercise the write without a widget *and* a screen cannot skip the
  /// confirmation by calling something cheaper.
  ///
  /// The first line is the duplicate-submission guard, and it is scoped to **this
  /// membership**: a second confirmation for a colleague whose request is already
  /// in flight returns immediately, without a second RPC. A request for any other
  /// colleague proceeds.
  Future<void> apply(
    String membershipId,
    RetailerStaffLifecycleAction action,
  ) async {
    if (state.isBusyFor(membershipId)) {
      return;
    }

    final int epoch = _epoch;
    final int generation = (_generations[membershipId] ?? 0) + 1;
    _generations[membershipId] = generation;

    // Starting a request clears whatever this row was last showing, and touches
    // no other row's entry.
    emit(
      state.copyWith(
        busyMembershipIds: <String>{...state.busyMembershipIds, membershipId},
        problems: _without(state.problems, membershipId),
        notices: _without(state.notices, membershipId),
      ),
    );

    // Exactly one call. The requested status comes from the action's own table —
    // the single place in this application a value destined for `p_status` is
    // produced.
    final RetailerStaffLifecycleResult result = await _repository
        .setMembershipStatus(
          membershipId: membershipId,
          status: action.requestedStatus,
        );

    if (isClosed) {
      return;
    }

    // A session change, or a roster change that dropped this target, or a
    // request this one was superseded by. Dropping the answer here is what stops
    // one Retailer's decision reporting into another's session — and what stops
    // a "now inactive" acknowledgement appearing beside a colleague it was never
    // about, or beside a card that is no longer on screen.
    //
    // Nothing is re-read on this path. For a session change there is nothing to
    // read for; for a departed membership the roster was just re-read (that is
    // how it departed), so a second call would learn nothing.
    if (epoch != _epoch || _generations[membershipId] != generation) {
      return;
    }

    final Set<String> stillBusy = <String>{...state.busyMembershipIds}
      ..remove(membershipId);

    switch (result) {
      case RetailerStaffLifecycleApplied(
        :final RetailerStaffLifecycleStatus confirmedStatus,
        :final bool statusChanged,
      ):
        // The notice is chosen from the status the DATABASE confirmed, never
        // from the one that was requested, and it distinguishes a real change
        // from an idempotent no-op because those mean different things to an
        // Owner.
        final RetailerStaffLifecycleNotice notice = switch ((
          confirmedStatus,
          statusChanged,
        )) {
          (RetailerStaffLifecycleStatus.deactivated, true) =>
            RetailerStaffLifecycleNotice.deactivated,
          (RetailerStaffLifecycleStatus.deactivated, false) =>
            RetailerStaffLifecycleNotice.alreadyInactive,
          (RetailerStaffLifecycleStatus.active, true) =>
            RetailerStaffLifecycleNotice.reactivated,
          (RetailerStaffLifecycleStatus.active, false) =>
            RetailerStaffLifecycleNotice.alreadyActive,
        };
        emit(
          state.copyWith(
            busyMembershipIds: stillBusy,
            notices: _with(state.notices, membershipId, notice),
          ),
        );
        await rereadRoster();

      case RetailerStaffLifecycleUnconfirmed():
        // No error, so the transaction committed — but the body could not be
        // trusted. Never reported as a refusal and never retried; the canonical
        // re-read is what then says which status the membership holds.
        emit(
          state.copyWith(
            busyMembershipIds: stillBusy,
            notices: _with(
              state.notices,
              membershipId,
              RetailerStaffLifecycleNotice.unconfirmed,
            ),
          ),
        );
        await rereadRoster();

      case RetailerStaffLifecycleRefused(
        :final RetailerStaffLifecycleProblem problem,
      ):
        // Nothing was written for the four SQLSTATE members, so the badge
        // already on screen is still correct and is left exactly as it is. The
        // roster is deliberately **not** re-read: a refusal changed nothing, and
        // re-reading would spend a request to learn that. The two unresolved
        // members say so in their own copy and point at a manual refresh.
        emit(
          state.copyWith(
            busyMembershipIds: stillBusy,
            problems: _with(state.problems, membershipId, problem),
          ),
        );
    }
  }

  /// Dismisses the outcome shown for one membership.
  ///
  /// Scoped like everything else: dismissing one colleague's acknowledgement
  /// leaves every other row untouched. A no-op while that row's request is in
  /// flight — there is nothing settled to dismiss.
  void dismiss(String membershipId) {
    if (state.isBusyFor(membershipId)) {
      return;
    }
    if (!state.problems.containsKey(membershipId) &&
        !state.notices.containsKey(membershipId)) {
      return;
    }
    emit(
      state.copyWith(
        problems: _without(state.problems, membershipId),
        notices: _without(state.notices, membershipId),
      ),
    );
  }

  /// Drops everything belonging to memberships the roster no longer contains.
  ///
  /// Called when the canonical roster changes underneath the cards — a refresh, a
  /// re-read, or a role switch that narrows what the backend returns.
  ///
  /// It acts on **in-flight requests as well as settled outcomes**, which the
  /// earlier design did not: a colleague who has left the roster is no longer a
  /// row an answer can be attached to, and an answer that arrived afterwards
  /// would attach itself to whichever row took its place. Bumping the departed
  /// membership's generation is what makes its eventual result inert.
  ///
  /// Memberships still present are untouched — their requests continue and their
  /// results still land.
  void rosterChanged(Iterable<String> membershipIds) {
    final Set<String> present = membershipIds.toSet();

    final Set<String> departed = <String>{
      ...state.busyMembershipIds,
      ...state.problems.keys,
      ...state.notices.keys,
    }..removeWhere(present.contains);

    if (departed.isEmpty) {
      return;
    }

    // Invalidate each departed membership's in-flight answer, if it has one.
    for (final String id in departed) {
      _generations[id] = (_generations[id] ?? 0) + 1;
    }

    emit(
      RetailerStaffLifecycleState(
        busyMembershipIds: Set<String>.unmodifiable(
          <String>{...state.busyMembershipIds}..removeWhere(departed.contains),
        ),
        problems: Map<String, RetailerStaffLifecycleProblem>.unmodifiable(
          <String, RetailerStaffLifecycleProblem>{...state.problems}
            ..removeWhere((String id, _) => departed.contains(id)),
        ),
        notices: Map<String, RetailerStaffLifecycleNotice>.unmodifiable(
          <String, RetailerStaffLifecycleNotice>{...state.notices}
            ..removeWhere((String id, _) => departed.contains(id)),
        ),
      ),
    );
  }

  /// Drops every pending decision, progress, result and error.
  ///
  /// Called when the signed-in person changes. A pending decision names a
  /// colleague in the previous Retailer's roster; advancing the epoch first means
  /// **every** request already in flight for them is dropped on arrival — not
  /// just the ones this cubit happens to hold a generation for — and certainly
  /// cannot leave a "now inactive" acknowledgement over somebody else's
  /// colleague.
  void clear() {
    _epoch++;
    _generations.clear();
    emit(const RetailerStaffLifecycleState());
  }

  static Map<String, T> _with<T>(Map<String, T> source, String key, T value) =>
      Map<String, T>.unmodifiable(<String, T>{...source, key: value});

  static Map<String, T> _without<T>(Map<String, T> source, String key) =>
      Map<String, T>.unmodifiable(<String, T>{...source}..remove(key));
}
