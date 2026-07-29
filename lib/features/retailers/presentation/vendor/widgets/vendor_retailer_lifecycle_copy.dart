/// Every sentence the Vendor Retailer lifecycle control can render.
///
/// Fixed local literals, all of them. Not one interpolates a relationship id, an
/// organization id, a raw status token, a SQLSTATE, a PostgREST detail, a
/// constraint name or a backend message — there is nothing of that kind
/// available at this layer to interpolate, because the repository hands the
/// screen a `Failure` discriminant and a confirmed status enum and nothing else.
///
/// The Retailer's **name** is the one dynamic value any of this may carry, it is
/// display text from a canonical read, and it appears only in a dialog title.
abstract final class VendorRetailerLifecycleCopy {
  // -------------------------------------------------------------------------
  // The section
  // -------------------------------------------------------------------------

  /// Deliberately **not** "Retailer status": the overview above this section
  /// already carries a `Retailer status` fact row, and two identical headings on
  /// one screen would leave a reader unable to tell which one the button acts
  /// on.
  static const String sectionTitle = 'Retailer lifecycle';

  /// Shown when the pair is ACTIVE/ACTIVE.
  static const String sectionActiveDescription =
      'This Retailer is active. Deactivating stops access for everyone at the '
      'Retailer while preserving their accounts, Shops, assignments, receipts '
      'and invitations.';

  /// Shown when the pair is SUSPENDED/SUSPENDED.
  static const String sectionInactiveDescription =
      'This Retailer is inactive. Reactivating restores access to the users, '
      'roles, Shops and assignments that were preserved.';

  // -------------------------------------------------------------------------
  // The actions
  // -------------------------------------------------------------------------

  static const String deactivate = 'Deactivate Retailer';
  static const String reactivate = 'Reactivate Retailer';
  static const String deactivating = 'Deactivating…';
  static const String reactivating = 'Reactivating…';
  static const String cancel = 'Cancel';

  static const String deactivateSemantics =
      'Deactivate this Retailer. Asks for confirmation first.';
  static const String reactivateSemantics =
      'Reactivate this Retailer. Asks for confirmation first.';

  // -------------------------------------------------------------------------
  // The confirmation dialogs
  //
  // Every clause below is a claim the deployed function proves. The words
  // "delete", "remove" and "erase" appear nowhere, because none of them happens:
  // the RPC moves two status columns and touches nothing else.
  // -------------------------------------------------------------------------

  static const String deactivateConfirmTitle = 'Deactivate Retailer?';

  static const String deactivateConfirmBody =
      'Retailer Owner, Manager and Sales Staff access to this Retailer will '
      'stop.\n\n'
      'People who are already signed in are blocked on their next refresh or '
      'protected action; they are not signed out.\n\n'
      'Receipt submission stops.\n\n'
      'New Shop creation, product assignment and invitation operations stop.\n\n'
      'Existing users, Shops, assignments, receipts and invitations are '
      'preserved. Nothing is deleted.\n\n'
      'Reactivating restores prior access wherever those records remain valid.';

  static const String reactivateConfirmTitle = 'Reactivate Retailer?';

  static const String reactivateConfirmBody =
      'The preserved users, roles, Shops and assignments become available '
      'again.\n\n'
      'Invitations that are still valid and unexpired become usable again.\n\n'
      'Receipt access resumes according to the permissions and Shop '
      'assignments each person already holds.';

  // -------------------------------------------------------------------------
  // Outcome notices
  //
  // Worded from the status the DATABASE confirmed, never from the one that was
  // requested.
  // -------------------------------------------------------------------------

  static const String deactivatedTitle = 'Retailer deactivated.';
  static const String deactivatedBody =
      'Everyone at this Retailer is blocked from their next request onward. '
      'Their accounts, Shops, assignments, receipts and invitations are '
      'unchanged.';

  static const String reactivatedTitle = 'Retailer reactivated.';
  static const String reactivatedBody =
      'Preserved users, roles, Shops and assignments are available again, and '
      'valid invitations can be used again.';

  /// The idempotent no-op. Nothing went wrong and nothing was written — most
  /// often somebody else got there first — so it is reported as an outcome
  /// rather than as an error.
  static const String alreadyInactiveTitle = 'No change was needed.';
  static const String alreadyInactiveBody =
      'This Retailer was already inactive.';

  static const String alreadyActiveTitle = 'No change was needed.';
  static const String alreadyActiveBody = 'This Retailer was already active.';

  /// The committed-but-undescribable case.
  ///
  /// It must not say "try again", "retry" or "resubmit": the transaction
  /// committed, so there is nothing to retry, and inviting a second attempt
  /// would ask somebody to repeat a decision that has already been recorded.
  static const String unconfirmedTitle = 'The change may have been saved.';
  static const String unconfirmedBody =
      'Refresh the Retailer to confirm its current status.';

  // -------------------------------------------------------------------------
  // Failure notices
  //
  // One wording per discriminant, and no wording names a cause the backend
  // refused to disclose.
  // -------------------------------------------------------------------------

  static const String failedTitle = 'Retailer status unchanged';

  static const String deniedTitle = 'Not allowed';
  static const String deniedBody =
      'This action is no longer allowed, or this Retailer is unavailable.';

  static const String signedOutTitle = 'Your session has ended';
  static const String signedOutBody = 'Sign in again to continue.';

  static const String invalidTitle = 'Not a valid change';
  static const String invalidBody = 'That Retailer status change is not valid.';

  /// `55000`. Four causes share this code and one message in SQL — an
  /// inconsistent pair, a `DEACTIVATED` row, **another Vendor still holding a
  /// live relationship with this Retailer**, and a compare-and-set row-count
  /// drift. They are indistinguishable on purpose: the multi-Vendor case must
  /// not disclose that another tenant exists. So this sentence names no cause,
  /// no count and no other organization.
  static const String notReadyTitle = 'Status change unavailable';
  static const String notReadyBody =
      'This Retailer’s lifecycle status cannot be changed right now.';

  static const String unavailableTitle = 'Could not change the status';
  static const String unavailableBody =
      'The Retailer status could not be changed. Nothing was retried '
      'automatically.';
}
