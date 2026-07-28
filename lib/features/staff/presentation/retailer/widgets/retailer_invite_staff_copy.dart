import '../../../../../core/errors/retailer_read_problem.dart';
import '../../../domain/entities/retailer_staff_invitation_request.dart';
import '../cubit/retailer_invite_staff_cubit.dart';

/// Every string the Invite Staff form renders.
///
/// Centralised for one reason above all: **no copy on this form may be derived
/// from a backend response.** Each string is a fixed literal chosen by a
/// discriminant, so an HTTP body, a PostgREST message, a SQLSTATE, a Resend
/// provider reply, a stack trace, an invitation id, a raw token, a token hash,
/// an accept link or any Supabase project detail cannot reach the screen through
/// any of them.
///
/// The only interpolated values anywhere in this feature are the shop names,
/// codes and cities the assignable-shops contract returns — the Owner's own
/// organization's data, and the very values the picker exists to show. **No shop
/// id is ever rendered**, here or anywhere else.
abstract final class RetailerInviteStaffCopy {
  static const String title = 'Invite a colleague';
  static const String description =
      'Send an invitation to join your organization. They will receive an '
      'email with a link to set up their account.';

  // -- fields ---------------------------------------------------------------

  static const String firstNameLabel = 'First name';
  static const String lastNameLabel = 'Last name';
  static const String emailLabel = 'Email address';
  static const String emailHint =
      'The invitation is sent to this address. Check it carefully — an '
      'invitation cannot be redirected once it is sent.';

  static const String roleLabel = 'Role';
  static const String roleHint =
      'Retailer Managers can see your whole team. Sales Staff submit receipts '
      'for the shops you assign them.';

  /// Deliberately **not** just "Shops".
  ///
  /// "Shops" is the Retailer Owner's navigation destination label, and a shell
  /// test asserts that no role's screen renders another role's destination
  /// labels — a genuinely useful check for cross-role leakage that a colliding
  /// field label would defeat. "Shops to assign" is also simply more accurate:
  /// these are the shops this person will work in, not a link to the estate.
  static const String shopsLabel = 'Shops to assign';
  static const String shopsHint =
      'Choose at least one shop this person will work in. Only shops that are '
      'currently active can be assigned.';

  static const String shopsLoading = 'Loading your active shops…';
  static const String shopsRetry = 'Try again';

  static const String shopsEmptyTitle = 'No active shops to assign';
  static const String shopsEmptyBody =
      'Sales Staff must be assigned to at least one active shop, and your '
      'organization has none right now. Invite a Retailer Manager instead, or '
      'ask your SalesReward contact to activate a shop.';

  static const String shopsDeniedTitle = 'You cannot assign shops';
  static const String shopsDeniedBody =
      'Your account is not permitted to assign shops to staff, so a Sales '
      'Staff invitation cannot be prepared here. You can still invite a '
      'Retailer Manager.';

  static const String shopsUnavailableTitle = 'Shops could not be loaded';

  /// Why the shop options could not be read.
  ///
  /// Deliberately **not** one sentence for every case: "check your connection"
  /// is right for exactly one of these and misleading for the rest.
  static String shopsProblemBody(RetailerReadProblem problem) =>
      switch (problem) {
        RetailerReadProblem.denied => shopsDeniedBody,
        RetailerReadProblem.signedOut =>
          'Your session has ended. Sign in again to assign shops.',
        RetailerReadProblem.malformed =>
          'SalesReward sent a list of shops this app could not read. Try '
              'again, and let us know if it keeps happening.',
        RetailerReadProblem.network =>
          'SalesReward could not be reached. Check your connection and try '
              'again.',
        RetailerReadProblem.timeout =>
          'Loading your shops took too long. Try again.',
        RetailerReadProblem.unexpected =>
          'Something went wrong while loading your shops. Try again.',
      };

  // -- submission -----------------------------------------------------------

  static const String submit = 'Send invitation';
  static const String submitting = 'Sending…';
  static const String refreshHistory = 'Refresh invitation history';

  // -- field messages -------------------------------------------------------

  /// The message under one control.
  ///
  /// Chosen from two discriminants — which control, and what is wrong with it —
  /// so every sentence is fixed at compile time.
  static String fieldMessage(
    RetailerStaffInvitationField field,
    RetailerStaffInvitationProblem problem,
  ) {
    return switch (problem) {
      RetailerStaffInvitationProblem.missing => switch (field) {
        RetailerStaffInvitationField.firstName => 'Enter their first name.',
        RetailerStaffInvitationField.lastName => 'Enter their last name.',
        RetailerStaffInvitationField.email => 'Enter their email address.',
        RetailerStaffInvitationField.role => 'Choose a role for this person.',
        RetailerStaffInvitationField.shops => shopsRequiredMessage,
      },
      RetailerStaffInvitationProblem.tooLong => switch (field) {
        RetailerStaffInvitationField.email =>
          'That email address is too long to send an invitation to.',
        _ => 'That name is longer than SalesReward can store.',
      },
      RetailerStaffInvitationProblem.malformed => switch (field) {
        RetailerStaffInvitationField.email =>
          'Enter a valid email address, like name@example.com.',
        // Only reachable if a selection did not come from the shop list, which
        // is a defect rather than a mistake. It still gets a sentence a person
        // can act on.
        _ => 'Reload your shops and choose them again.',
      },
      RetailerStaffInvitationProblem.shopsRequired => shopsRequiredMessage,
      RetailerStaffInvitationProblem.shopsNotAllowed =>
        'Retailer Managers are not assigned to individual shops.',
      RetailerStaffInvitationProblem.duplicateShops =>
        'The same shop was chosen twice. Reload your shops and try again.',
      RetailerStaffInvitationProblem.tooManyShops =>
        'That is more shops than one invitation can cover.',
    };
  }

  static const String shopsRequiredMessage =
      'Choose at least one shop for a Sales Staff member.';

  // -- form-level notices ---------------------------------------------------

  static String noticeTitle(
    RetailerInviteStaffNotice notice,
  ) => switch (notice) {
    RetailerInviteStaffNotice.checkTheForm => 'Check the form',
    RetailerInviteStaffNotice.sent => 'Invitation sent',
    RetailerInviteStaffNotice.resent => 'A new invitation was sent',
    RetailerInviteStaffNotice.deliveryUnconfirmed =>
      'The invitation status could not be confirmed',
    RetailerInviteStaffNotice.timedOut =>
      'The invitation status could not be confirmed',
    RetailerInviteStaffNotice.unreadableAnswer =>
      'The invitation status could not be confirmed',
    RetailerInviteStaffNotice.unexpected =>
      'The invitation status could not be confirmed',
    RetailerInviteStaffNotice.deliveryFailed =>
      'The invitation email could not be delivered',
    RetailerInviteStaffNotice.invalidRequest => 'The invitation was refused',
    RetailerInviteStaffNotice.invalidRoleShopCombination =>
      'The role and shops do not match',
    RetailerInviteStaffNotice.signedOut => 'Your session has ended',
    RetailerInviteStaffNotice.accessDenied => 'You cannot invite staff',
    RetailerInviteStaffNotice.invitationConflict =>
      'This person already has an invitation',
    RetailerInviteStaffNotice.retailerInactive =>
      'Your organization cannot invite staff right now',
    RetailerInviteStaffNotice.featureDisabled => 'Invitations are switched off',
    RetailerInviteStaffNotice.notConfigured =>
      'Invitations are unavailable right now',
    RetailerInviteStaffNotice.serviceFault =>
      'The invitation could not be sent',
    RetailerInviteStaffNotice.network => 'SalesReward could not be reached',
  };

  static String noticeBody(
    RetailerInviteStaffNotice notice,
  ) => switch (notice) {
    RetailerInviteStaffNotice.checkTheForm =>
      'Nothing was sent. Fix the highlighted fields and try again.',

    RetailerInviteStaffNotice.sent =>
      'The invitation email is on its way. It appears in the invitation '
          'history below with its current status.',

    // A resend rotates the token, so the earlier link stops working. Saying so
    // matters: somebody chasing an older email needs to know to use the new one.
    RetailerInviteStaffNotice.resent =>
      'A new invitation email has been sent, and the previous invitation link '
          'is no longer current. The invitation history below shows where it '
          'stands.',

    // The 202 case, and the one sentence the milestone specifies almost
    // verbatim. It never says the invitation failed, and it never invites an
    // immediate second attempt.
    RetailerInviteStaffNotice.deliveryUnconfirmed =>
      'The email may have been sent, but the latest invitation status could '
          'not be confirmed. Refresh the invitation history before trying '
          'again.',

    RetailerInviteStaffNotice.timedOut =>
      'SalesReward did not answer in time, so the email may still have been '
          'sent. Refresh the invitation history before trying again.',

    RetailerInviteStaffNotice.unreadableAnswer =>
      'SalesReward answered in a way this app could not read, so the email may '
          'still have been sent. Refresh the invitation history before trying '
          'again.',

    RetailerInviteStaffNotice.unexpected =>
      'Something went wrong after the invitation was submitted, so the email '
          'may still have been sent. Refresh the invitation history before '
          'trying again.',

    RetailerInviteStaffNotice.deliveryFailed =>
      'The invitation exists, but the email was not accepted for delivery. '
          'Check the address, then send it again when you are ready.',

    RetailerInviteStaffNotice.invalidRequest =>
      'Nothing was sent. Check the details you entered and try again.',

    RetailerInviteStaffNotice.invalidRoleShopCombination =>
      'Nothing was sent. Sales Staff need at least one shop, and Retailer '
          'Managers are not assigned to shops.',

    RetailerInviteStaffNotice.signedOut =>
      'Nothing was sent. Sign in again, then send the invitation.',

    RetailerInviteStaffNotice.accessDenied =>
      'Nothing was sent. Your account is not permitted to invite staff for '
          'this organization.',

    // Deliberately vague about what differs. The backend refuses this with one
    // byte-identical exception so an invitation cannot be used to probe who
    // exists, and restating the difference here would undo that.
    RetailerInviteStaffNotice.invitationConflict =>
      'Nothing was sent. There is already a live invitation for this address '
          'with different details. Ask your SalesReward contact to revoke it, '
          'then invite them again.',

    RetailerInviteStaffNotice.retailerInactive =>
      'Nothing was sent. Your organization is not active, so new staff cannot '
          'be invited. Contact your SalesReward representative.',

    RetailerInviteStaffNotice.featureDisabled =>
      'Nothing was sent. Staff invitations are switched off for SalesReward at '
          'the moment. Try again later.',

    RetailerInviteStaffNotice.notConfigured =>
      'Nothing was sent. Invitations cannot be delivered at the moment. Try '
          'again later, and let us know if it keeps happening.',

    RetailerInviteStaffNotice.serviceFault =>
      'Nothing was sent. Something went wrong on our side. Try again in a few '
          'minutes.',

    RetailerInviteStaffNotice.network =>
      'Nothing was sent. Check your connection and try again.',
  };

  /// Shown beside a send's own notice when the canonical history could not be
  /// re-read afterwards.
  ///
  /// Never phrased as a send failure — the invitation is exactly as sent as the
  /// notice above it says — and the only action it offers is a **read**.
  static const String historyRereadFailedTitle =
      'The invitation history could not be reloaded';
  static const String historyRereadFailedBody =
      'This does not change what happened to the invitation. The list below is '
      'the last one that loaded, so it may not show the newest invitation yet.';
}
