import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/retailer_read_problem.dart';
import '../../../domain/entities/retailer_staff_invitation.dart';
import '../../../domain/entities/retailer_staff_member.dart';
import '../../../domain/repositories/retailer_staff_repository.dart';

part 'retailer_staff_state.dart';

/// The calling Retailer member's staff view.
///
/// Backed by `list_retailer_staff_members()` and, for a caller who holds
/// `RETAILER_STAFF_MANAGE`, `list_retailer_staff_invitations()`. Both take zero
/// arguments and resolve their tenant from `auth.uid()`.
///
/// ## Two sections, two independent outcomes
///
/// The roster and the invitation history are **companion reads, not a
/// transaction**. They sit on different permissions and can genuinely disagree,
/// so each has its own phase, its own rows and its own problem in
/// [RetailerStaffState]. The consequences are deliberate:
///
/// * a roster that loaded is **never erased** because the invitation history
///   failed, and vice versa;
/// * the screen never claims both failed when only one did;
/// * a refresh re-reads both, but their answers are applied independently as
///   they arrive.
///
/// ## Whether invitations are read at all is set once, at construction
///
/// [includeInvitations] is supplied by the shell from the role whose shell it
/// is: the Owner shell passes true, the Manager shell false. It is **not** a
/// permission check — the backend decides that and would refuse a Manager with
/// `42501` regardless. It exists so the Manager screen does not issue a request
/// whose only possible outcome is a refusal, which would put a denial notice on
/// a screen where nothing is wrong.
///
/// If a Manager's role were granted the permission tomorrow, nothing here would
/// need to change for the read to start succeeding — the flag would simply be
/// flipped in the shell.
///
/// ## Search is local
///
/// [searchChanged] filters rows **already read** and issues no request, so a
/// search term never reaches the backend and can never become a predicate the
/// database evaluates. One term filters both sections, because a person looking
/// for "Priya" wants her wherever she appears.
final class RetailerStaffCubit extends Cubit<RetailerStaffState> {
  RetailerStaffCubit(this._repository, {required this.includeInvitations})
    : super(const RetailerStaffState());

  final RetailerStaffRepository _repository;

  /// Whether this shell's role is the one the invitation contract serves.
  ///
  /// Presentation scope, never authorization — see the class doc.
  final bool includeInvitations;

  /// Discriminates the answers this cubit is waiting for. A single token covers
  /// both reads: a session change invalidates everything at once, and there is
  /// no case in which one section's stale answer should be accepted while the
  /// other's is dropped.
  int _token = 0;

  /// Exposed for the isolation tests.
  int get requestToken => _token;

  /// Reads both sections, showing the full loading state.
  Future<void> load() => _fetch(showLoading: true);

  /// Re-reads both sections in place, keeping current rows on screen.
  Future<void> refresh() => _fetch(showLoading: !state.hasAnyContent);

  /// Loads only if nothing has been read yet.
  ///
  /// What makes "opening the tab reads once" and "returning to a loaded tab
  /// reads nothing" both true without the page knowing which case it is in.
  Future<void> loadOnce() {
    if (state.rosterPhase != RetailerStaffPhase.initial) {
      return Future<void>.value();
    }
    return load();
  }

  Future<void> _fetch({required bool showLoading}) async {
    // One in-flight pass at a time. A second call is a no-op rather than a
    // queued duplicate.
    if (state.isRefreshing) {
      return;
    }

    final int token = ++_token;

    emit(
      state.copyWith(
        rosterPhase: showLoading
            ? RetailerStaffPhase.loading
            : RetailerStaffPhase.ready,
        invitationPhase: !includeInvitations
            ? RetailerStaffPhase.notApplicable
            : (showLoading
                  ? RetailerStaffPhase.loading
                  : RetailerStaffPhase.ready),
        isRefreshing: true,
        clearRosterProblem: true,
        clearInvitationProblem: true,
      ),
    );

    // Started together so the two round trips overlap rather than queue. They
    // are still applied independently below — `Future.wait` here is about
    // latency, not about coupling their outcomes.
    final Future<RetailerStaffResult> roster = _repository.members();
    final Future<RetailerInvitationsResult>? invites = includeInvitations
        ? _repository.invitations()
        : null;

    final RetailerStaffResult rosterResult = await roster;
    final RetailerInvitationsResult? invitationResult = await invites;

    if (isClosed || token != _token) {
      return;
    }

    RetailerStaffState next = state.copyWith(isRefreshing: false);

    switch (rosterResult) {
      case RetailerStaffLoaded(:final List<RetailerStaffMember> members):
        next = next.copyWith(
          rosterPhase: RetailerStaffPhase.ready,
          members: members,
          clearRosterProblem: true,
        );
      case RetailerStaffFailed(:final RetailerReadProblem problem):
        next = next.copyWith(
          rosterPhase: RetailerStaffPhase.failed,
          rosterProblem: problem,
          // Rows already on screen stay. They are still the last thing the
          // backend actually said.
        );
    }

    switch (invitationResult) {
      case null:
        // Not read for this role. Deliberately not a failure and not an empty
        // list — the section simply does not exist on this screen.
        next = next.copyWith(
          invitationPhase: RetailerStaffPhase.notApplicable,
          clearInvitationProblem: true,
        );
      case RetailerInvitationsLoaded(
        :final List<RetailerStaffInvitation> invitations,
      ):
        next = next.copyWith(
          invitationPhase: RetailerStaffPhase.ready,
          invitations: invitations,
          clearInvitationProblem: true,
        );
      case RetailerInvitationsFailed(:final RetailerReadProblem problem):
        next = next.copyWith(
          invitationPhase: RetailerStaffPhase.failed,
          invitationProblem: problem,
        );
    }

    emit(next);
  }

  /// Re-reads **only** the invitation history, and reports whether it landed.
  ///
  /// ## Why the invite form needs this rather than [refresh]
  ///
  /// The send contract's response carries no invitation record — deliberately,
  /// because a returned row would be a second invitation shape free to drift
  /// from the one `list_retailer_staff_invitations()` returns. So after a send
  /// the only honest way to show what now exists is to re-read the canonical
  /// history, and **nothing is ever appended locally**: a row assembled from the
  /// form would state a `derived_state`, an `expires_at` and a `sent_at` this
  /// client never received.
  ///
  /// The roster is left alone. Sending an invitation creates no membership, so
  /// re-reading the roster would be a request whose answer cannot have changed.
  ///
  /// ## The return value is the whole point
  ///
  /// `false` means the send's own result stands but the history beside it is
  /// stale. The caller must **not** turn that into "the invitation failed" — the
  /// invitation is exactly as sent as the send result said it was — and must not
  /// repeat the send to resolve it. Rows already on screen are kept, and the
  /// screen's own Refresh remains available.
  ///
  /// Returns `false` immediately when this screen has no invitation section, so
  /// a caller cannot accidentally issue a read whose only outcome is a refusal.
  Future<bool> rereadInvitations() async {
    if (!includeInvitations) {
      return false;
    }

    // Supersedes any pass already in flight, exactly as `_fetch` does. The token
    // is what stops that older pass from writing its answer over this one.
    final int token = ++_token;

    emit(
      state.copyWith(
        invitationPhase: state.invitations == null
            ? RetailerStaffPhase.loading
            : RetailerStaffPhase.ready,
        isRefreshing: true,
        clearInvitationProblem: true,
      ),
    );

    final RetailerInvitationsResult result = await _repository.invitations();

    if (isClosed || token != _token) {
      return false;
    }

    switch (result) {
      case RetailerInvitationsLoaded(
        :final List<RetailerStaffInvitation> invitations,
      ):
        emit(
          state.copyWith(
            invitationPhase: RetailerStaffPhase.ready,
            invitations: invitations,
            isRefreshing: false,
            clearInvitationProblem: true,
          ),
        );
        return true;
      case RetailerInvitationsFailed(:final RetailerReadProblem problem):
        emit(
          state.copyWith(
            invitationPhase: RetailerStaffPhase.failed,
            invitationProblem: problem,
            isRefreshing: false,
            // Rows already on screen stay. They are still the last thing the
            // backend actually said, and the invitation just sent is missing
            // from them — which the notice above the form says in words.
          ),
        );
        return false;
    }
  }

  /// Filters the rows already held. Issues no request.
  void searchChanged(String term) {
    emit(state.copyWith(searchTerm: term));
  }

  /// Drops both sections, the search term, the loading and refresh state and
  /// both problems.
  ///
  /// Called when the signed-in person or the resolved Retailer changes. This is
  /// the most personal data in the portal — colleagues' names, their roles,
  /// their membership standing, which shops they work in, and the email
  /// addresses invitations were sent to — and the search term is private too,
  /// being a fragment of one of those names.
  ///
  /// Advancing the token first means answers already in flight for the previous
  /// identity cannot refill either section after it has been emptied.
  void clear() {
    _token++;
    emit(const RetailerStaffState());
  }
}
