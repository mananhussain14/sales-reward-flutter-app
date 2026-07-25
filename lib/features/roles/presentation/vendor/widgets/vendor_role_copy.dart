/// Every user-facing sentence this feature renders, in one place.
///
/// Centralised for the same reason the receipt, Retailer and User features
/// centralise theirs: a string that explains a *backend* answer is part of the
/// security boundary, not decoration. The rules these strings obey:
///
/// * **No raw backend text.** No Postgres message, SQLSTATE, table, column,
///   function or policy name appears in any of them.
/// * **An inaccessible role is never described as somebody else's.**
///   [detailNotFoundTitle] and [detailNotFoundBody] are the single wording for
///   an unknown id, an id belonging to another table and a malformed id alike.
///   "This role belongs to another Vendor" would be *false* as well as leaky:
///   the catalogue is global and there is no such thing as another Vendor's
///   role.
/// * **The catalogue is described as shared, in plain words.** A Vendor who sees
///   Retailer Owner in their own Roles screen must be able to read why, without
///   the screen inventing a scope the schema does not have.
/// * **Mapped is never called effective.** [permissionsDescription] says what
///   the list is; [inactiveNoticeBody] says when it does not apply. Neither ever
///   claims the person reading it holds these permissions.
/// * **Nothing here names a write.** There is no create, edit, delete, activate,
///   deactivate, duplicate, assign or remove string, because there is no such
///   backend anywhere in the product — on web or mobile.
/// * **An outage is never a denial**, and a denial never reads as "not found".
///   Those two live in `SrFailureView`, which this feature reuses rather than
///   rewording.
abstract final class VendorRoleCopy {
  // -- the catalogue ---------------------------------------------------------

  static const String listTitle = 'Roles';

  /// States the global-catalogue fact and the one tenant-scoped fact together,
  /// because each is misleading without the other.
  static const String listDescription =
      'Shared role catalogue. Every organization on the platform uses the same '
      'role definitions, so Retailer roles appear here too. Member counts are '
      'for your Vendor organization.';

  /// Repeated beside the rows, where a reader is actually looking at a Retailer
  /// role and wondering why.
  static const String sharedCatalogueNote =
      'These definitions are shared platform-wide and are read-only. Only the '
      'member counts below are specific to your Vendor organization.';

  static const String searchLabel = 'Search roles';
  static const String searchPlaceholder = 'Search by role name';
  static const String searchHint =
      'Filters the roles already loaded. Nothing is sent to the server.';

  static const String statusFilterLabel = 'Role status';
  static const String filterAll = 'All';

  static const String refresh = 'Refresh';
  static const String refreshing = 'Refreshing…';
  static const String clearFilters = 'Clear filters';

  static const String loadingList = 'Loading roles';

  static const String emptyTitle = 'No roles to show';
  static const String emptyBody =
      'There are no role definitions on record. Roles are defined by the '
      'platform and cannot be created here.';

  static const String noMatchesTitle = 'No roles match';
  static const String noMatchesBody =
      'No loaded role matches the current search or status filter.';

  static const String staleListTitle = 'This list may be out of date';
  static const String staleListBody =
      'We could not refresh the role catalogue just now.';

  static const String openDetails = 'View details';

  static const String totalLabel = 'Roles in catalogue';
  static const String totalHint = 'Shared across every organization';
  static const String activeLabel = 'Active roles';
  static const String activeHint = 'Their mapped permissions are effective';
  static const String inactiveLabel = 'Inactive roles';
  static const String inactiveHint = 'Mapped permissions are not effective';

  /// Deliberately "mappings" rather than "permissions": a permission mapped to
  /// three roles is counted three times, and calling the total "permissions"
  /// would claim a catalogue size the contract does not report.
  static const String mappingsLabel = 'Permission mappings';
  static const String mappingsHint = 'Across every role in the catalogue';

  // -- one role --------------------------------------------------------------

  static const String detailEyebrow = 'Role definition';
  static const String backToList = 'Back to Roles';
  static const String loadingDetail = 'Loading role';

  static const String overviewTitle = 'Definition';

  static const String statusLabel = 'Role status';
  static const String createdLabel = 'Created';
  static const String descriptionLabel = 'Description';
  static const String permissionCountLabel = 'Permissions mapped';
  static const String assignedMembersLabel = 'Members in your Vendor';

  /// Shown where a nullable description is absent. A phrase rather than a blank
  /// or an em dash — a screen reader announcing "dash" tells nobody anything —
  /// and never a sentence invented from the role name.
  static const String noDescription = 'No description';

  /// The single wording for every role id this caller cannot address.
  static const String detailNotFoundTitle = 'Role not available';

  /// Says nothing about whether the role exists, and offers no retry — the
  /// backend already answered, and it will answer the same way.
  static const String detailNotFoundBody =
      'This role is not available to your account. The link may be out of date '
      'or may not name a role.';

  // -- permissions -----------------------------------------------------------

  static const String permissionsTitle = 'Permissions';

  /// The careful sentence. The list describes the **role**, not the reader.
  static const String permissionsDescription =
      'The permissions mapped to this role definition.';

  static const String permissionsEmptyTitle = 'No permissions assigned';
  static const String permissionsEmptyBody =
      'This role definition has no permissions mapped to it.';

  static const String permissionsUnavailableTitle = 'Permissions unavailable';
  static const String permissionsUnavailableBody =
      'We could not load the permissions for this role. The role details above '
      'are still current.';
  static const String retryPermissions = 'Try again';

  /// A permission with no stored description.
  static const String noPermissionDescription = 'No description';

  /// Surfaced when the role row and the permission list disagree about how many
  /// mappings there are. Every returned row is still shown and the count is
  /// still reported unchanged.
  static const String countMismatchTitle = 'This list may have just changed';
  static const String countMismatchBody =
      'The number of mapped permissions recorded for this role does not match '
      'the list below. Everything returned is shown. Refresh to read both '
      'again.';

  // -- role status semantics -------------------------------------------------

  static const String inactiveNoticeTitle = 'This role is inactive';

  /// The sentence the whole feature exists to get right.
  static const String inactiveNoticeBody =
      'Its mapped permissions are not currently effective. They are still '
      'listed below so you can see what the definition holds.';

  static const String inactiveNoticeSemantics =
      'Inactive role. Mapped permissions are not currently effective.';

  /// A status token this build does not recognise. Neutral, and never
  /// affirmative about effectiveness.
  static const String unknownStatusNoticeTitle = 'Unrecognised role status';
  static const String unknownStatusNoticeBody =
      'This role has a status this version of the app does not recognise, so '
      'whether its mapped permissions are effective cannot be shown here.';

  static const String unknownStatusNoticeSemantics =
      'Unrecognised role status. Whether the mapped permissions are effective '
      'is not shown.';
}
