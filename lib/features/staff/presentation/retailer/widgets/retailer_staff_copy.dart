/// Every string the Retailer Staff screen renders.
///
/// Centralised for one reason above all: **no copy on this screen may be derived
/// from a backend response.** Each string is a fixed literal, so a Postgres
/// message, a SQLSTATE, a stack trace, a UUID or an internal enum token cannot
/// reach the screen through any of them.
///
/// The only interpolated values in this feature are people's names, their shop
/// names and the email address an invitation was sent to — all display data the
/// contracts exist to return, and all already the Owner's own organization's
/// data.
abstract final class RetailerStaffCopy {
  static const String title = 'Staff';

  /// Deliberately different for the two roles, because what the screen contains
  /// is different — an Owner sees invitation history and a Manager does not, and
  /// a shared description would over-promise to one of them.
  static const String ownerDescription =
      'The people in your organization, and the invitations you have sent.';
  static const String managerDescription =
      'The active members of your organization.';

  static const String loading = 'Loading your staff…';
  static const String refresh = 'Refresh';
  static const String refreshing = 'Refreshing…';

  // -- search ---------------------------------------------------------------

  static const String searchLabel = 'Search staff';
  static const String searchPlaceholder = 'Name, role, shop or email';
  static const String searchHint =
      'Filters the staff already loaded, by name, role, shop or invited email.';

  static const String searchEmptyTitle = 'No staff match that search';
  static const String searchEmptyBody =
      'Clear the search to see everyone again.';

  // -- roster ---------------------------------------------------------------

  static const String rosterTitle = 'Staff members';
  static const String rosterEmptyTitle = 'No staff members yet';
  static const String rosterEmptyBody =
      'People appear here once they accept an invitation to your '
      'organization.';

  /// Shown to a Manager, whose backend read is narrowed to ACTIVE members.
  ///
  /// Says what is on screen without asserting a permission the client has not
  /// checked and does not enforce.
  static const String managerScopeNote =
      'This list shows the active members of your organization.';

  static const String noShopsLabel = 'No shops assigned';

  /// Deliberately **not** just "Shops".
  ///
  /// "Shops" is the Retailer Owner's navigation destination label, and a shell
  /// test asserts that no role's screen renders another role's destination
  /// labels — a genuinely useful check for cross-role leakage. A field label
  /// that collides with a destination label defeats it. "Assigned shops" is also
  /// simply more accurate: these are the shops this person works in, not a link
  /// to the estate.
  static const String shopsLabel = 'Assigned shops';
  static const String roleLabel = 'Role';
  static const String joinedLabel = 'Joined';
  static const String joinedUnknown = 'Not recorded';

  // -- invitations ----------------------------------------------------------

  static const String invitationsTitle = 'Invitation history';
  static const String invitationsDescription =
      'Every invitation sent for your organization, and what happened to it.';

  static const String invitationsEmptyTitle = 'No invitations yet';
  static const String invitationsEmptyBody =
      'Invitations you send appear here with their current status.';

  /// The milestone boundary, stated plainly rather than implied by an absent
  /// button. Sending an invitation needs the delivery service, which the app
  /// does not talk to.
  static const String invitationsReadOnlyNote =
      'This history is read-only. Sending, resending and revoking invitations '
      'are done on the SalesReward web portal.';

  static const String invitedAsLabel = 'Invited as';
  static const String sentLabel = 'Sent';
  static const String acceptedLabel = 'Accepted';
  static const String revokedLabel = 'Revoked';
  static const String expiresLabel = 'Expires';
  static const String expiredLabel = 'Expired';
  static const String createdLabel = 'Created';
  static const String neverSent = 'Not sent';

  /// The delivery-failure notice.
  ///
  /// Safe copy by construction: it describes the outcome a person can act on and
  /// never carries `failure_code`, which is reduced to a boolean at the parser
  /// and does not exist beyond it.
  static const String deliveryFailedLabel = 'Email not delivered';
  static const String deliveryFailedHint =
      'SalesReward could not deliver this invitation email. Check the address '
      'and send a new invitation from the web portal.';

  /// The label for a role a person was invited as.
  ///
  /// The invitation contract returns **only `role_code`**, unlike the roster
  /// which returns a display name too. So the code is mapped here through a
  /// fixed table rather than rendered raw.
  ///
  /// An unrecognised code — a role added after this build — falls back to a
  /// neutral phrase rather than showing the token. `SALES_STAFF` on screen would
  /// be an internal identifier leaking into the UI.
  static String roleLabelFor(String roleCode) => switch (roleCode) {
    'RETAILER_OWNER' => 'Retailer Owner',
    'RETAILER_MANAGER' => 'Retailer Manager',
    'SALES_STAFF' => 'Sales Staff',
    _ => 'Another role',
  };

  // -- section-level failures ----------------------------------------------

  /// Used when one section failed and the other did not, so the screen never
  /// claims both failed.
  static const String rosterSectionFailed = 'Staff members could not be loaded';
  static const String invitationsSectionFailed =
      'Invitation history could not be loaded';

  static const String staleTitle = 'Showing the last loaded staff';
  static const String staleBody =
      'The most recent refresh did not complete, so this may be out of date. '
      'Try refreshing again.';

  static String showing(int visible, int total) =>
      visible == total ? '$total people' : 'Showing $visible of $total';
}
