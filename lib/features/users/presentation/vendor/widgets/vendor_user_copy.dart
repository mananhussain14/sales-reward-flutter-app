/// Every user-facing sentence this feature renders, in one place.
///
/// Centralised for the same reason the receipt and Retailer features centralise
/// theirs: a string that explains a *backend* answer is part of the security
/// boundary, not decoration. The rules these strings obey:
///
/// * **No raw backend text.** No Postgres message, SQLSTATE, table, column,
///   function or policy name appears in any of them.
/// * **An inaccessible membership is never described as somebody else's.**
///   [detailNotFoundTitle] and [detailNotFoundBody] are the single wording for
///   an unknown id, another Vendor's id, a Retailer-owned membership id and a
///   malformed id alike. Saying "this user belongs to another Vendor" would
///   confirm existence and undo the indistinguishable zero-row answer the SQL is
///   careful to give.
/// * **Nothing here mentions email, a phone number or an invitation.** The
///   backend returns no address and there is no Vendor invitation table in the
///   schema, so a string about either would describe a feature that does not
///   exist. There is no "Email unavailable" row for the same reason: a label for
///   an absent field is still a claim about it.
/// * **An outage is never a denial**, and a denial never reads as "not found".
///   Those two live in `SrFailureView`, which this feature reuses rather than
///   rewording.
abstract final class VendorUserCopy {
  // -- the directory ---------------------------------------------------------

  static const String listTitle = 'Users';

  static const String listDescription =
      'Everyone with a membership in your Vendor organization, with the roles '
      'each one holds. Open a user to see their full record.';

  static const String searchLabel = 'Search users';
  static const String searchPlaceholder = 'Search by name';
  static const String searchHint =
      'Filters the users already loaded. Nothing is sent to the server.';

  static const String profileFilterLabel = 'Profile status';
  static const String membershipFilterLabel = 'Membership status';
  static const String filterAll = 'All';

  static const String refresh = 'Refresh';
  static const String refreshing = 'Refreshing…';
  static const String clearFilters = 'Clear filters';

  static const String loadingList = 'Loading users';

  /// Written against **one** row rather than zero.
  ///
  /// An authorized caller is by definition an active member of the Vendor they
  /// are listing, so their own row is always present — "this Vendor has no
  /// users" is not a state the backend can produce for someone who can see the
  /// screen. The real case is "it is just me".
  static const String onlyMeTitle = 'You are the only user';
  static const String onlyMeBody =
      'Nobody else has a membership in this Vendor organization yet. Users are '
      'added from the web admin.';

  /// The defensive floor: a genuinely empty response. Kept for resilience.
  static const String emptyTitle = 'No users to show';
  static const String emptyBody =
      'This Vendor organization has no user memberships on record.';

  static const String noMatchesTitle = 'No users match';
  static const String noMatchesBody =
      'No loaded user matches the current search or status filters.';

  static const String staleListTitle = 'This list may be out of date';
  static const String staleListBody =
      'We could not refresh your users just now.';

  static const String openDetails = 'View details';

  /// Deliberately not just "Users": the page is already titled that, and a stat
  /// card repeating the page title reads as a heading rather than a figure.
  static const String totalLabel = 'Total users';
  static const String totalHint = 'Memberships in this Vendor organization';
  static const String activeLabel = 'Active memberships';

  /// Not just "Invited": a bare status word would be indistinguishable from the
  /// filter chip of the same name sitting a few pixels below it.
  static const String invitedLabel = 'Invited users';
  static const String inactiveLabel = 'Suspended or deactivated';

  // -- one user --------------------------------------------------------------

  static const String detailEyebrow = 'Vendor user';
  static const String backToList = 'Back to Users';
  static const String loadingDetail = 'Loading user';

  static const String overviewTitle = 'Membership';

  static const String profileStatusLabel = 'Profile status';
  static const String membershipStatusLabel = 'Membership status';
  static const String membershipCreatedLabel = 'Membership created';
  static const String joinedLabel = 'Joined';
  static const String deactivatedLabel = 'Deactivated';

  /// Shown when `joined_at` is null. A statement about the date, not about the
  /// status — the status has its own badge and is never inferred from a date.
  static const String notJoinedYet = 'Not joined yet';

  /// The single wording for every membership this caller cannot address.
  static const String detailNotFoundTitle = 'User not available';

  /// Deliberately says nothing about whether the user exists, and offers no
  /// retry — the backend already answered, and it will answer the same way.
  static const String detailNotFoundBody =
      'This user is not available to your account. The link may be out of date, '
      'or the membership may no longer be part of your organization.';

  // -- roles -----------------------------------------------------------------

  static const String rolesTitle = 'Roles';

  /// The wording the web uses for the same case, so the two clients agree.
  static const String noRoles = 'No active role';

  static const String noRolesBody =
      'This user holds no active role in your organization.';
}
