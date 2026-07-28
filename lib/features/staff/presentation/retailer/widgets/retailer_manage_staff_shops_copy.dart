import '../../../../../core/errors/retailer_read_problem.dart';
import '../../../domain/entities/retailer_staff_shop_assignment.dart';
import '../cubit/retailer_manage_staff_shops_cubit.dart';

/// Every string the Manage Shops editor renders.
///
/// Centralised for one reason above all: **no copy on this surface may be
/// derived from a backend response.** Each string is a fixed literal chosen by a
/// discriminant, so a PostgreSQL message, a SQLSTATE, a PostgREST detail or
/// hint, a function or table name, a membership id, a shop id, a stack trace or
/// a Supabase project URL cannot reach the screen through any of them.
///
/// The only interpolated values anywhere in this feature are a colleague's name,
/// their role's display name, and the names, codes and cities of their own
/// organization's shops — all display data the contracts exist to return. **No
/// identifier of any kind is ever rendered.**
abstract final class RetailerManageStaffShopsCopy {
  // -- the roster control ---------------------------------------------------

  static const String action = 'Manage shops';

  /// Spoken by the roster card's button. Names the colleague so a screen-reader
  /// user knows which card's control they are on, and nothing else.
  static String actionSemantics(String name) =>
      'Manage shops for $name. Opens a dialog.';

  // -- the editor -----------------------------------------------------------

  static const String title = 'Manage shops';

  static const String description =
      'Choose every shop this person should work in. Saving replaces their '
      'current shops with exactly what is selected here.';

  static const String currentLabel = 'Currently assigned';
  static const String currentNone = 'No shops assigned right now';

  static const String optionsLabel = 'Active shops';
  static const String optionsHint =
      'At least one shop is required. Only shops that are currently active can '
      'be assigned.';

  static const String optionsLoading = 'Loading your active shops…';
  static const String optionsRetry = 'Try again';

  static const String optionsEmptyTitle = 'No active shops to assign';
  static const String optionsEmptyBody =
      'A Sales Staff member must work in at least one active shop, and your '
      'organization has none right now. Ask your SalesReward contact to '
      'activate a shop.';

  static const String optionsUnavailableTitle = 'Shops could not be loaded';

  /// Why the **options read** did not answer.
  ///
  /// Deliberately never worded as a save failure: nothing has been written, the
  /// roster underneath is untouched, and the only action offered is the read
  /// again.
  static String optionsProblemBody(RetailerReadProblem problem) =>
      switch (problem) {
        RetailerReadProblem.denied =>
          'You do not have permission to assign shops for your organization. '
              'If that is unexpected, ask another owner to check your access.',
        RetailerReadProblem.signedOut =>
          'Your session has ended. Sign in again to choose shops.',
        RetailerReadProblem.malformed =>
          'SalesReward returned something this version could not read. Try '
              'again, and update the app if it keeps happening.',
        RetailerReadProblem.network =>
          'SalesReward could not be reached. Check your connection and try '
              'again.',
        RetailerReadProblem.timeout =>
          'Loading your shops took too long. Try again.',
        RetailerReadProblem.unexpected =>
          'Something went wrong while loading your shops. Try again.',
      };

  /// The count line above the picker.
  static String selectedCount(int count) => switch (count) {
    0 => 'No shops selected',
    1 => '1 shop selected',
    _ => '$count shops selected',
  };

  static const String availabilityChangedTitle = 'Shop availability changed';
  static const String availabilityChangedBody =
      'One or more shops you had selected are no longer available to assign, '
      'so they have been removed from your selection. Review the shops below '
      'before saving.';
  static const String availabilityChangedAction = 'Review and continue';

  static const String save = 'Save changes';
  static const String saving = 'Saving…';
  static const String cancel = 'Cancel';

  /// Spoken by the Save button. States the consequence, because this control
  /// replaces a colleague's shops rather than adding to them.
  static const String saveSemantics =
      'Save changes. Replaces this person\'s active shops with the selection.';

  // -- validation -----------------------------------------------------------

  /// The message under one control. Built from a discriminant, never from a
  /// backend answer.
  static String fieldMessage(
    RetailerStaffShopAssignmentField field,
    RetailerStaffShopAssignmentInputProblem problem,
  ) => switch (problem) {
    RetailerStaffShopAssignmentInputProblem.noShopsSelected =>
      'Select at least one shop.',
    RetailerStaffShopAssignmentInputProblem.missingTarget =>
      'This staff member is no longer available. Close this and try again.',
    RetailerStaffShopAssignmentInputProblem.malformed => switch (field) {
      RetailerStaffShopAssignmentField.target =>
        'This staff member could not be identified. Refresh the staff list and '
            'try again.',
      RetailerStaffShopAssignmentField.shops =>
        'One of the selected shops could not be identified. Reload the shops '
            'and try again.',
    },
  };

  // -- the result -----------------------------------------------------------

  static String noticeTitle(RetailerManageShopsNotice notice) =>
      switch (notice) {
        RetailerManageShopsNotice.checkTheSelection => 'Check the selection',
        RetailerManageShopsNotice.targetUnavailable =>
          'That staff member is no longer listed',
        RetailerManageShopsNotice.saved => 'Shop assignments updated',
        RetailerManageShopsNotice.timedOut => 'This took too long to confirm',
        RetailerManageShopsNotice.unreadableAnswer =>
          'The result could not be read',
        RetailerManageShopsNotice.unexpected => 'The result is not confirmed',
        RetailerManageShopsNotice.accessDenied => 'Shops were not changed',
        RetailerManageShopsNotice.invalidSelection =>
          'That selection cannot be saved',
        RetailerManageShopsNotice.retailerUnavailable =>
          'Shops cannot be changed right now',
        RetailerManageShopsNotice.invalidRequest => 'Shops were not changed',
        RetailerManageShopsNotice.signedOut => 'Your session has ended',
        RetailerManageShopsNotice.network => 'SalesReward could not be reached',
      };

  /// The sentence under [noticeTitle].
  ///
  /// [change] is consulted only for the success case, which is the one notice
  /// whose wording depends on what the backend counted. Every other branch is a
  /// fixed literal that no response can influence.
  static String noticeBody(
    RetailerManageShopsNotice notice, {
    RetailerStaffShopAssignmentChange? change,
  }) => switch (notice) {
    RetailerManageShopsNotice.checkTheSelection =>
      'Nothing was sent. Fix the highlighted item and try again.',

    RetailerManageShopsNotice.targetUnavailable =>
      'The staff list changed while the editor was open, so the change was not '
          'sent. Open the person again from the refreshed list.',

    // Delegated, so the counts are put into words in exactly one place and no
    // caller can assemble a different sentence from them.
    RetailerManageShopsNotice.saved =>
      change == null ? 'The change was saved.' : savedBody(change),

    // The three unresolved outcomes. Each says plainly that the change may
    // already have been made and points at the roster — never at the button.
    RetailerManageShopsNotice.timedOut =>
      'SalesReward did not answer in time, so this change may or may not have '
          'been saved. Refresh the staff list to see the current shops before '
          'trying again.',
    RetailerManageShopsNotice.unreadableAnswer =>
      'SalesReward answered with something this version could not read, so '
          'this change may or may not have been saved. Refresh the staff list '
          'to see the current shops.',
    RetailerManageShopsNotice.unexpected =>
      'Something went wrong after the change was sent, so it may or may not '
          'have been saved. Refresh the staff list to see the current shops.',

    // The definite refusals. Nothing was written; the selection is still on
    // screen for a deliberate retry.
    //
    // `accessDenied` covers "you may not", "that person is not in your
    // organization" and "that person no longer exists" together, because the
    // backend answers all three identically so that this operation cannot be
    // used to find out who exists. This sentence must not narrow that.
    RetailerManageShopsNotice.accessDenied =>
      'You cannot change this person\'s shops. Your access or their membership '
          'may have changed — refresh the staff list to see the current '
          'details.',
    RetailerManageShopsNotice.invalidSelection =>
      'At least one active shop is required, and every shop must be one of '
          'your organization\'s active shops. Reload the shops and choose '
          'again.',
    RetailerManageShopsNotice.retailerUnavailable =>
      'Your organization is not currently able to accept staff changes. Contact '
          'your SalesReward representative.',
    RetailerManageShopsNotice.invalidRequest =>
      'This version could not put the request together correctly. Refresh the '
          'staff list and try again, and update the app if it keeps happening.',
    RetailerManageShopsNotice.signedOut =>
      'Sign in again to change shop assignments.',
    RetailerManageShopsNotice.network =>
      'The change was not sent. Check your connection and try again.',
  };

  /// The change summary sentence.
  ///
  /// ## What it deliberately never says
  ///
  /// It never adds counts together and calls the result a total. The three
  /// counts describe the **visible ACTIVE replacement** only: a member may also
  /// hold assignments to shops that are no longer active, which no read returns
  /// and the save preserved untouched. "Now works in 4 shops" would be a claim
  /// this client has no basis for, and the refreshed staff list below is the
  /// authority.
  ///
  /// It also never names a shop. Which shop was added or removed is visible on
  /// the refreshed card, from the canonical read, rather than restated here from
  /// what was submitted.
  static String savedBody(RetailerStaffShopAssignmentChange change) {
    if (!change.hasChanges) {
      return 'The shops selected were already assigned, so nothing changed.';
    }

    final List<String> parts = <String>[
      if (change.shopsAdded > 0) _shops(change.shopsAdded, 'added'),
      if (change.shopsRemoved > 0) _shops(change.shopsRemoved, 'removed'),
    ];

    return '${parts.join(' and ')}.';
  }

  static String _shops(int count, String verb) =>
      count == 1 ? '1 shop $verb' : '$count shops $verb';

  // -- roster reread --------------------------------------------------------

  static const String rosterRereadFailedTitle =
      'The staff list could not be refreshed';

  /// Stated as two separate facts, in that order, because conflating them is the
  /// one failure mode this whole path exists to avoid: the write **was**
  /// committed, and only the read beside it did not land.
  static const String rosterRereadFailedBody =
      'Shop assignments were updated, but the latest staff details could not '
      'be refreshed, so the list below may be out of date.';

  static const String refreshRoster = 'Refresh staff list';
}
