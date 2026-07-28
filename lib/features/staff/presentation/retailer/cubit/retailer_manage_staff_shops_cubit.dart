import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/retailer_read_problem.dart';
import '../../../domain/entities/retailer_assignable_shop.dart';
import '../../../domain/entities/retailer_staff_member.dart';
import '../../../domain/entities/retailer_staff_shop_assignment.dart';
import '../../../domain/repositories/retailer_assignable_shops_reader.dart';
import '../../../domain/repositories/retailer_staff_shop_assignment_repository.dart';

part 'retailer_manage_staff_shops_state.dart';

/// Re-reads the canonical staff roster and reports whether it landed.
///
/// A function rather than a reference to the staff cubit, so this cubit owns no
/// other cubit and a test can drive "the write succeeded but the roster did not
/// reload" without standing up a second bloc.
typedef RetailerStaffRosterReread = Future<bool> Function();

/// The Owner's Manage Shops editor for one existing Sales Staff member.
///
/// Backed by `list_retailer_staff_assignable_shops()` for the options and by
/// `set_retailer_staff_shop_assignments(uuid, uuid[])` for the save. The read
/// takes zero arguments; the write takes exactly the membership id and the
/// complete desired ACTIVE shop set, and no identity of any kind.
///
/// ## Why this is a cubit of its own
///
/// [RetailerStaffCubit] owns two reads that must survive anything this editor
/// does. Combining them would mean a save failure sat in the same state object
/// as the roster, one `copyWith` away from clearing it — and the roster,
/// invitation history, search term and Invite Staff form must all be untouched
/// by a shop edit that went wrong. Separate cubits make that structural rather
/// than remembered.
///
/// ## Presentation scope, never authorization
///
/// This cubit is provided only in the Retailer Owner shell, and the control that
/// opens it is offered only for a row the backend already described as an active,
/// accepted Sales Staff member. Both are courtesies: they stop a control whose
/// only outcome would be a refusal from reaching a screen. The database decides
/// — it re-derives the caller, the Retailer, the permission, the target's role
/// and status, and every shop, on every call — and a hidden button is not a
/// security boundary.
///
/// ## The complete desired set, never a diff
///
/// [submittableShopIds] is the whole ACTIVE set the Owner wants, intersected
/// with the options the backend most recently returned. The client computes no
/// additions and no removals; the function does, which is why the counts come
/// back rather than going out.
///
/// ## What the editor can and cannot see
///
/// Only ACTIVE shops. A member may hold a live assignment to a suspended or
/// deactivated shop that no contract returns; the write **preserves** it, this
/// editor never names it, and no copy anywhere claims the visible list is
/// everything.
///
/// ## One save per submission, and no automatic retry anywhere
///
/// [save] refuses to start while one is in flight, so a double tap cannot
/// produce two writes. Nothing here retries on failure, on timeout, on an
/// unreadable answer, or — most importantly — after a success: a committed
/// change is closed out of the editor entirely, so an ordinary retry has nothing
/// left to resubmit.
///
/// ## The roster is re-read, never patched
///
/// The write's response carries three counts and no assignment rows, so nothing
/// is assembled locally. [RetailerStaffRosterReread] re-reads
/// `list_retailer_staff_members()`, and a reread that fails is reported as
/// exactly that — the change was still committed, and it is never restated as a
/// failure because the read beside it did not land.
final class RetailerManageStaffShopsCubit
    extends Cubit<RetailerManageStaffShopsState> {
  RetailerManageStaffShopsCubit({
    required RetailerAssignableShopsReader shops,
    required RetailerStaffShopAssignmentRepository assignments,
    required RetailerStaffRosterReread rereadRoster,
  }) : _shops = shops,
       _assignments = assignments,
       _rereadRoster = rereadRoster,
       super(const RetailerManageStaffShopsState());

  final RetailerAssignableShopsReader _shops;
  final RetailerStaffShopAssignmentRepository _assignments;
  final RetailerStaffRosterReread _rereadRoster;

  /// Discriminates the answers this cubit is waiting for.
  ///
  /// One token covers the options read, the save and the roster reread together:
  /// a session change, a Retailer change or a change of target invalidates
  /// everything at once, and there is no case in which a previous identity's or
  /// a previous colleague's answer should be accepted for one of them while
  /// being dropped for another.
  int _token = 0;

  /// Exposed for the isolation tests.
  int get requestToken => _token;

  // -- opening and closing --------------------------------------------------

  /// Opens the editor for [member] and reads the assignable shops.
  ///
  /// The target is addressed by [RetailerStaffMember.membershipId] — the value
  /// `list_retailer_staff_members()` returned — and never by an auth user id, a
  /// profile id, an email, an invitation id, a member-role id, a name or a
  /// position in the list. Two colleagues may share a name; a position is a
  /// property of one response rather than of a person.
  ///
  /// Refused for a row the roster did not describe as an active, accepted Sales
  /// Staff member. Presentation scope again: the function refuses the same rows
  /// on its own terms, and this only avoids opening an editor that could not
  /// save.
  ///
  /// The options are re-read on **every** open rather than cached across one,
  /// because shop availability is exactly the thing that goes stale: a shop
  /// suspended since the last look must not still be offered, and the
  /// preselection has to be intersected with what is assignable *now*.
  void open(RetailerStaffMember member) {
    if (state.isSubmitting || !member.isEditableSalesStaff) {
      return;
    }

    // Advanced before anything is requested, so an options read, a save or a
    // roster reread still in flight for the *previous* target is dropped on
    // arrival rather than filling this one's editor with another colleague's
    // shops.
    _token++;

    emit(
      RetailerManageStaffShopsState(
        // The address, held for exactly as long as the editor is open.
        membershipId: member.membershipId,
        // Display values, carried so the editor can name the person and show
        // what they hold today without a second read.
        staffName: member.fullName,
        roleName: member.roleName,
        currentShopNames: List<String>.unmodifiable(member.shopNames),
        // The roster's ACTIVE ids. Not yet the selection: it becomes one only
        // after being intersected with the options the read returns.
        rosterShopIds: Set<String>.unmodifiable(member.shopIds),
        isOpen: true,
      ),
    );

    loadAssignableShops();
  }

  /// Closes the editor and drops everything it held about the target.
  ///
  /// The last result is deliberately **kept**: it is shown beside the roster,
  /// which is where a committed change is acknowledged next to the rows it
  /// changed. Everything else — the membership id, the selection, the options,
  /// the person's name — goes, because none of it belongs on screen once the
  /// editor is gone.
  ///
  /// A no-op while a save is in flight. Closing then would leave a write with
  /// nowhere to report, and the surface keeps its own controls disabled for the
  /// same reason.
  void closeEditor() {
    if (state.isSubmitting || !state.isOpen) {
      return;
    }
    _token++;
    emit(
      RetailerManageStaffShopsState(
        notice: state.notice,
        change: state.change,
        rosterRereadFailed: state.rosterRereadFailed,
      ),
    );
  }

  /// Closes the editor if the roster no longer contains the open target.
  ///
  /// Called when the canonical roster changes underneath the editor — a refresh,
  /// a reread, or a role switch that narrows what the backend returns. A person
  /// who has left the organization, been deactivated, or been re-roled is no
  /// longer a target this operation can address, and an editor left open over
  /// one would be collecting a selection with nowhere to send it.
  ///
  /// Deliberately does nothing while a save is in flight: that write already
  /// names the target, and the answer decides what happened to it.
  void rosterChanged(Iterable<String> membershipIds) {
    final String? target = state.membershipId;
    if (!state.isOpen || state.isSubmitting || target == null) {
      return;
    }
    if (membershipIds.contains(target)) {
      return;
    }
    _token++;
    emit(
      const RetailerManageStaffShopsState(
        notice: RetailerManageShopsNotice.targetUnavailable,
      ),
    );
  }

  // -- options --------------------------------------------------------------

  /// Reads `list_retailer_staff_assignable_shops()`.
  ///
  /// Zero arguments. No Retailer organization id is sent, because the deployed
  /// function has no parameter for one and derives the Retailer from
  /// `auth.uid()` — and **no membership id is sent either**: the list is the
  /// Retailer's assignable estate, not "the shops available to this person", so
  /// the target's address has no business travelling on a read that does not
  /// need it.
  ///
  /// A failure is scoped to the editor. The roster underneath keeps its rows and
  /// its own state, the retry offered is this **read** alone, and Save is
  /// disabled — a read that did not answer is never converted into a write
  /// failure.
  Future<void> loadAssignableShops() async {
    if (!state.isOpen || state.isOptionsLoading) {
      return;
    }

    final int token = ++_token;
    emit(
      state.copyWith(
        optionsPhase: RetailerManageShopsOptionsPhase.loading,
        clearOptionsProblem: true,
      ),
    );

    final RetailerAssignableShopsResult result = await _shops.assignableShops();

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case RetailerAssignableShopsLoaded(
        :final List<RetailerAssignableShop> shops,
      ):
        _applyOptions(shops);
      case RetailerAssignableShopsFailed(:final RetailerReadProblem problem):
        emit(
          state.copyWith(
            optionsPhase: RetailerManageShopsOptionsPhase.failed,
            optionsProblem: problem,
          ),
        );
    }
  }

  /// Reconciles a fresh option list with whatever is currently ticked.
  ///
  /// Two cases, and they are told apart deliberately:
  ///
  /// * **First load.** Nothing has been ticked yet, so the selection starts as
  ///   the roster's ACTIVE ids **intersected** with the options. A roster id the
  ///   options no longer offer is a shop that stopped being ACTIVE between the
  ///   two reads; it is dropped silently and correctly, because it is a hidden
  ///   non-ACTIVE assignment the write preserves rather than something the
  ///   person deselected.
  /// * **A later load** — a retry, or a reopen. A tick for a shop this response
  ///   no longer offers is removed from the valid set and flagged, because that
  ///   one *is* a choice this person made and having it silently vanish, or
  ///   silently ride along in a request the function would refuse, are both
  ///   worse than saying availability changed and asking them to look.
  void _applyOptions(List<RetailerAssignableShop> shops) {
    final Set<String> available = shops
        .map((RetailerAssignableShop shop) => shop.id)
        .toSet();

    // "Has a read ever produced options for this target?" — and deliberately not
    // the phase, which this very call already moved to `loading`. A retry after
    // a failure is still a first load, because the failed attempt produced
    // nothing to have ticked.
    final bool isFirstLoad = state.shops == null;

    final Set<String> desired = isFirstLoad
        ? state.rosterShopIds
        : state.selectedShopIds;

    final Set<String> kept = desired.where(available.contains).toSet();
    final bool droppedSomething = kept.length != desired.length;

    emit(
      state.copyWith(
        optionsPhase: RetailerManageShopsOptionsPhase.ready,
        shops: shops,
        selectedShopIds: Set<String>.unmodifiable(kept),
        // The baseline for "has anything changed?" is what the editor actually
        // started from, not the raw roster set: a shop that is no longer
        // assignable was never on offer here, so leaving it out is not an edit
        // the person made.
        baselineShopIds: isFirstLoad
            ? Set<String>.unmodifiable(kept)
            : state.baselineShopIds,
        // Only a *ticked* shop disappearing warrants the notice. A roster id
        // dropped on first load is the ACTIVE projection doing its job.
        availabilityChanged: !isFirstLoad && droppedSomething,
        clearOptionsProblem: true,
      ),
    );
  }

  /// Acknowledges that shop availability changed, re-arming Save.
  ///
  /// The one thing that must not happen when an option disappears is a silent
  /// submission of a set the person never reviewed. So Save stays disabled until
  /// this is called — by a deliberate press, or implicitly by changing the
  /// selection, which is itself a review.
  void acknowledgeAvailabilityChange() {
    if (!state.availabilityChanged) {
      return;
    }
    emit(state.copyWith(availabilityChanged: false));
  }

  // -- selection ------------------------------------------------------------

  /// Ticks or unticks one option.
  ///
  /// Keyed on the id the backend returned, held in a `Set` so a duplicate is
  /// structurally impossible. A shop's **name** and its **position in the list**
  /// are never used to identify it: two shops may legitimately share a name, and
  /// a position is a property of one response rather than of a shop.
  ///
  /// An id that is not in the current options is ignored outright, so nothing
  /// can tick a shop this Retailer was not offered.
  void shopSelectionToggled(String shopId) {
    if (!state.isOpen || state.isSubmitting) {
      return;
    }
    final List<RetailerAssignableShop> options =
        state.shops ?? const <RetailerAssignableShop>[];
    if (!options.any((RetailerAssignableShop shop) => shop.id == shopId)) {
      return;
    }

    final Set<String> next = Set<String>.of(state.selectedShopIds);
    if (!next.remove(shopId)) {
      next.add(shopId);
    }

    emit(
      state.copyWith(
        selectedShopIds: Set<String>.unmodifiable(next),
        // Changing the selection *is* the review the availability notice asked
        // for, so it clears here too.
        availabilityChanged: false,
        // A stale result above a selection being re-edited would describe a save
        // that is no longer the one on screen.
        clearNotice: true,
        rosterRereadFailed: false,
      ),
    );
  }

  // -- saving ---------------------------------------------------------------

  /// Validates, writes once, and re-reads the canonical roster.
  Future<void> save() async {
    // The whole double-submit guard. The button is disabled too, but a disabled
    // button is a courtesy and this is the rule: a queued second tap, a rebuild
    // racing a rebuild, or a keyboard activation arriving beside a press all
    // land here.
    if (state.isSubmitting || !state.isOpen) {
      return;
    }

    final RetailerStaffShopAssignmentInput input =
        RetailerStaffShopAssignmentRequest.validated(
          membershipId: state.membershipId,
          // Already intersected with the options the backend returned, so an id
          // that is no longer assignable — or was never in a response at all —
          // cannot be sent.
          shopIds: state.submittableShopIds,
        );

    if (input case RetailerStaffShopAssignmentInvalid(
      :final Map<
        RetailerStaffShopAssignmentField,
        RetailerStaffShopAssignmentInputProblem
      >
      problems,
    )) {
      // Nothing left the device.
      emit(
        state.copyWith(
          fieldProblems: problems,
          notice: RetailerManageShopsNotice.checkTheSelection,
          rosterRereadFailed: false,
        ),
      );
      return;
    }

    final RetailerStaffShopAssignmentRequest request =
        (input as RetailerStaffShopAssignmentValid).request;

    final int token = ++_token;
    emit(
      state.copyWith(
        isSubmitting: true,
        fieldProblems:
            const <
              RetailerStaffShopAssignmentField,
              RetailerStaffShopAssignmentInputProblem
            >{},
        clearNotice: true,
        rosterRereadFailed: false,
      ),
    );

    final RetailerStaffShopAssignmentResult result = await _assignments
        .setShopAssignments(request);

    // A result for a session, a Retailer, or a target that is no longer the
    // current one is dropped on arrival. It must not put the previous identity's
    // success on somebody else's screen, and it must not reopen an editor that
    // has just been emptied.
    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case RetailerStaffShopAssignmentApplied(
        :final RetailerStaffShopAssignmentChange change,
      ):
        // Committed. The editor is closed out entirely rather than left armed,
        // which is what makes an ordinary retry impossible: there is no target
        // and no selection left to resubmit.
        emit(
          RetailerManageStaffShopsState(
            notice: RetailerManageShopsNotice.saved,
            change: change,
          ),
        );

        final bool reread = await _rereadRoster();

        if (isClosed || token != _token || reread) {
          return;
        }

        // The save stands exactly as reported above. Only the roster beside it
        // is stale, and the action offered for that is a read.
        emit(state.copyWith(rosterRereadFailed: true));

      case RetailerStaffShopAssignmentRefused(
        :final RetailerStaffShopAssignmentProblem problem,
      ):
        emit(
          state.copyWith(
            isSubmitting: false,
            notice: _noticeFor(problem),
            // The editor stays open with the selection intact for a *definite*
            // refusal, so a deliberate retry costs no re-ticking. For the three
            // unresolved outcomes the notice says the change may already have
            // been made and points at the roster — see the notice's own doc.
          ),
        );
    }
  }

  static RetailerManageShopsNotice _noticeFor(
    RetailerStaffShopAssignmentProblem problem,
  ) => switch (problem) {
    RetailerStaffShopAssignmentProblem.denied =>
      RetailerManageShopsNotice.accessDenied,
    RetailerStaffShopAssignmentProblem.invalidSelection =>
      RetailerManageShopsNotice.invalidSelection,
    RetailerStaffShopAssignmentProblem.retailerUnavailable =>
      RetailerManageShopsNotice.retailerUnavailable,
    RetailerStaffShopAssignmentProblem.malformedRequest =>
      RetailerManageShopsNotice.invalidRequest,
    RetailerStaffShopAssignmentProblem.signedOut =>
      RetailerManageShopsNotice.signedOut,
    RetailerStaffShopAssignmentProblem.malformedResponse =>
      RetailerManageShopsNotice.unreadableAnswer,
    RetailerStaffShopAssignmentProblem.network =>
      RetailerManageShopsNotice.network,
    RetailerStaffShopAssignmentProblem.timeout =>
      RetailerManageShopsNotice.timedOut,
    RetailerStaffShopAssignmentProblem.unexpected =>
      RetailerManageShopsNotice.unexpected,
  };

  /// Drops the target, the selection, the options, the result, every message,
  /// the editor's visibility and the in-flight token.
  ///
  /// Called when the signed-in person, the resolved Retailer or the active role
  /// changes. What it protects is real: one colleague's membership address, the
  /// shops they work in, and one Retailer's whole assignable estate with its
  /// ids — none of which belongs on the next session's screen for even an
  /// instant.
  ///
  /// Advancing the token first means an options read, a save, or a roster reread
  /// already in flight for the previous identity is dropped on arrival rather
  /// than refilling an editor that has just been emptied — including a save
  /// whose answer was already on its way when the session ended.
  void clear() {
    _token++;
    emit(const RetailerManageStaffShopsState());
  }
}
