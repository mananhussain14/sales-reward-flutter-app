import '../../../domain/repositories/retailer_staff_lifecycle_repository.dart';
import '../cubit/retailer_staff_lifecycle_cubit.dart';

/// Every sentence the Retailer staff lifecycle control can render.
///
/// Fixed local literals, all of them. Not one interpolates a membership id, a
/// role code, a raw status token, a SQLSTATE, a PostgREST detail, a constraint
/// name or a backend message — there is nothing of that kind available at this
/// layer to interpolate, because the repository hands the screen a problem
/// discriminant and a confirmed-status enum and nothing else.
///
/// The colleague's **name** is the one dynamic value any of this carries, it is
/// display text from the canonical roster, and it appears only in a dialog title
/// and a semantics label.
///
/// ## The refusal copy discloses nothing
///
/// `42501` covers eleven causes with one message in SQL — among them "the target
/// is a Retailer Owner", "the target is you", "the target holds several roles",
/// "the target is invited", "the target is suspended" and "that membership
/// belongs to another Retailer". [problemBody] gives all of them **one** sentence
/// that names none of them. A caller must not be able to sweep membership ids and
/// read another Retailer's org chart out of the wording.
abstract final class RetailerStaffLifecycleCopy {
  // -------------------------------------------------------------------------
  // Confirmation dialogs
  //
  // Every clause is a claim the deployed function proves. The words "delete",
  // "remove" and "erase" appear nowhere, because none of them happens: the RPC
  // moves two columns and touches nothing else.
  // -------------------------------------------------------------------------

  static const String cancel = 'Cancel';

  static const String deactivateBody =
      'They will lose access to the Retailer workspace, including receipt '
      'submission.\n\n'
      'Anyone already signed in is blocked the next time they open, refresh or '
      'do anything that reaches the server. They are not signed out.\n\n'
      'Their profile, sign-in, role and Shop assignments are kept, along with '
      'their receipts and history. Nothing is deleted.\n\n'
      'You can reactivate them at any time, and their previous access returns.';

  static const String reactivateBody =
      'They will be able to use the Retailer workspace again straight away.\n\n'
      'Their previous role and Shop assignments were never removed, so access '
      'returns exactly as it was. Nothing needs to be set up again.\n\n'
      'Receipt access resumes according to the role and Shop assignments they '
      'already hold.';

  /// The dialog body for [action]'s direction.
  static String confirmBody({required bool isDeactivation}) =>
      isDeactivation ? deactivateBody : reactivateBody;

  /// The accessible name of the card control, naming the person it acts on.
  static String actionSemantics(
    String memberName, {
    required bool isDeactivation,
  }) => isDeactivation
      ? 'Deactivate $memberName. Asks for confirmation first.'
      : 'Reactivate $memberName. Asks for confirmation first.';

  // -------------------------------------------------------------------------
  // Outcome notices
  //
  // Worded from the status the DATABASE confirmed, never from the one requested.
  // -------------------------------------------------------------------------

  static String noticeTitle(RetailerStaffLifecycleNotice notice) =>
      switch (notice) {
        RetailerStaffLifecycleNotice.deactivated => 'Staff member deactivated',
        RetailerStaffLifecycleNotice.reactivated => 'Staff member reactivated',
        RetailerStaffLifecycleNotice.alreadyInactive ||
        RetailerStaffLifecycleNotice.alreadyActive => 'No change was needed',
        RetailerStaffLifecycleNotice.unconfirmed =>
          'The status change may have been saved',
      };

  static String noticeBody(
    RetailerStaffLifecycleNotice notice,
  ) => switch (notice) {
    RetailerStaffLifecycleNotice.deactivated =>
      'They are now inactive and no longer have access. Their role, Shops, '
          'receipts and history are unchanged.',
    RetailerStaffLifecycleNotice.reactivated =>
      'They are now active again. Their previous role and Shop assignments '
          'are available.',
    RetailerStaffLifecycleNotice.alreadyInactive =>
      'That staff member was already inactive.',
    RetailerStaffLifecycleNotice.alreadyActive =>
      'That staff member was already active.',
    // Must not say "try again", "retry" or "resubmit": the transaction
    // committed, so there is nothing to retry, and inviting a second attempt
    // would ask somebody to repeat a decision already recorded.
    RetailerStaffLifecycleNotice.unconfirmed =>
      'Check the staff list below to confirm the current status.',
  };

  // -------------------------------------------------------------------------
  // Refusal notices
  // -------------------------------------------------------------------------

  static String problemTitle(RetailerStaffLifecycleProblem problem) =>
      switch (problem) {
        RetailerStaffLifecycleProblem.denied => 'Status not changed',
        RetailerStaffLifecycleProblem.invalidStatus => 'Status not changed',
        RetailerStaffLifecycleProblem.retailerUnavailable =>
          'Your Retailer is not available',
        RetailerStaffLifecycleProblem.malformedRequest => 'Status not changed',
        RetailerStaffLifecycleProblem.signedOut => 'Your session has ended',
        RetailerStaffLifecycleProblem.network => 'Could not reach SalesReward',
        RetailerStaffLifecycleProblem.timeout => 'This took too long',
        RetailerStaffLifecycleProblem.unexpected => 'Something went wrong',
      };

  static String problemBody(
    RetailerStaffLifecycleProblem problem,
  ) => switch (problem) {
    // One sentence for eleven causes. It names no role, no relationship, no
    // other organization and no reason.
    RetailerStaffLifecycleProblem.denied =>
      "You can't change this person's status. Refresh the staff list and "
          'try again.',
    RetailerStaffLifecycleProblem.invalidStatus =>
      "That status change isn't valid. Refresh the staff list and try "
          'again.',
    // Safe to word specifically: this is a fact about the caller's OWN
    // organization, not about the target.
    RetailerStaffLifecycleProblem.retailerUnavailable =>
      'Your Retailer is not available right now, so the status could not be '
          'changed. Nothing was changed.',
    RetailerStaffLifecycleProblem.malformedRequest =>
      'That request could not be sent. Refresh the staff list and try '
          'again.',
    RetailerStaffLifecycleProblem.signedOut =>
      'Sign in again to continue. Nothing was changed.',
    RetailerStaffLifecycleProblem.network =>
      'Check your connection and try again. Nothing was changed.',
    // The two unresolved outcomes. Both point at the roster rather than at
    // the button, because the write may have committed after this device
    // stopped waiting — and neither is retried automatically.
    RetailerStaffLifecycleProblem.timeout =>
      'The status change may or may not have been applied. Refresh the '
          'staff list to see the current status.',
    RetailerStaffLifecycleProblem.unexpected =>
      'The status change may or may not have been applied. Refresh the '
          'staff list to see the current status.',
  };
}
