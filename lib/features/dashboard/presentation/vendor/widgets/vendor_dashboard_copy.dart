/// Every user-facing sentence this feature renders, in one place.
///
/// Centralised for the same reason the Retailer, User, Role, Product and Audit
/// features centralise theirs — but here the stakes are unusual, because on this
/// screen **the labels are the contract**. Four numbers with no context are four
/// claims, and two of them are claims about the deployment rather than about the
/// organization whose name sits at the top of the page.
///
/// The rules these strings obey:
///
/// * **No raw backend text.** No Postgres message, SQLSTATE, table, column,
///   function, policy or permission name appears in any of them. A caller whose
///   role no longer holds one of the three read permissions the summary requires
///   sees the same generic wording as a caller who is not signed in.
/// * **A global figure is never called the Vendor's.** `public.roles` and
///   `public.permissions` carry no `organization_id`, so
///   [activeRoleDefinitionsLabel] and [permissionDefinitionsLabel] show the same
///   number to every authorized Vendor. "Your roles", "Vendor roles", "Roles
///   assigned in this organization", "Your permissions" and "Assigned
///   permissions" would each state something false, and none of them appears
///   here.
/// * **Members are memberships, not people.** [activeMembersLabel] counts
///   `organization_members` rows with `status = 'ACTIVE'`. It does not join
///   `profiles`, so it is not "active profiles"; it excludes INVITED, so it is
///   not "all users"; and one membership counts once however many roles it
///   carries, so it is not "users with roles".
/// * **Audit events are all-time.** [auditEventsLabel] has no window. "Recent",
///   "Today", "This week" and "Last 30 days" are windows this product does not
///   define anywhere, so none of them is implied.
/// * **Nothing claims a trend.** No string here says a figure rose, fell, or
///   compares to anything. The contract returns four scalars and no history, so
///   there is no comparison to describe.
/// * **An outage is never a denial**, and a denial never reads as "this Vendor
///   has nothing". Those two live in `SrFailureView`, which this feature reuses
///   rather than rewording.
abstract final class VendorDashboardCopy {
  // -- the page --------------------------------------------------------------

  static const String title = 'Dashboard';

  /// Says what the four figures are, and — in one clause — that two of them are
  /// not this organization's. The scope note is load-bearing rather than modest:
  /// without it a reader would reasonably take every number on an organization
  /// overview to be a property of that organization, and for half of them that is
  /// untrue.
  static const String description =
      'A read-only overview of this Vendor organization, alongside the shared '
      'access catalogue every organization in SalesReward uses.';

  /// Labels the organization name taken from the trusted session context.
  ///
  /// "Signed in to" rather than "Showing data for": the name describes **who the
  /// caller is administering**, and only two of the four figures below belong to
  /// it. A caption that promised otherwise would undo the section headings.
  static const String organizationLabel = 'Signed in to';

  static const String refresh = 'Refresh';
  static const String refreshing = 'Refreshing…';

  /// Generic by design. A loading state must not name a record, an organization
  /// or a person, because it must not leak what is being loaded.
  static const String loading = 'Loading dashboard summary';

  static const String staleTitle = 'These figures may be out of date';
  static const String staleBody =
      'We could not refresh the summary just now. The figures already loaded '
      'are still shown.';

  // -- the Vendor-scoped section ---------------------------------------------

  static const String vendorSectionTitle = 'This Vendor organization';
  static const String vendorSectionDescription =
      'Counted for the organization named above.';

  /// The scope chip on every Vendor-scoped card.
  ///
  /// Text, not colour. The distinction between a tenant figure and a catalogue
  /// figure is the single most misreadable thing on this screen, so it is stated
  /// three times over — in the section heading, in this chip, and in each card's
  /// own hint — and never by tone alone.
  static const String vendorScopeChip = 'This organization';

  static const String activeMembersLabel = 'Active members';
  static const String activeMembersHint =
      'Active memberships in this Vendor organization';

  static const String auditEventsLabel = 'Audit events';
  static const String auditEventsHint = 'All recorded Vendor events';

  /// Says the one thing about this figure a reader could otherwise get wrong.
  static const String auditEventsNote =
      'This is the all-time total for this organization. There is no time '
      'window and no filter.';

  // -- the shared catalogue section ------------------------------------------

  static const String catalogueSectionTitle = 'Shared access catalogue';

  /// States plainly that these two figures are not the organization's.
  static const String catalogueSectionDescription =
      'Defined once for all of SalesReward. These two figures are the same for '
      'every organization and are not counted for this one.';

  /// The scope chip on every catalogue card.
  static const String catalogueScopeChip = 'Shared catalogue';

  static const String activeRoleDefinitionsLabel = 'Active role definitions';
  static const String activeRoleDefinitionsHint =
      'Available across the shared role catalogue';

  static const String permissionDefinitionsLabel = 'Permission definitions';
  static const String permissionDefinitionsHint =
      'Available across the shared permission catalogue';

  // -- quick links -----------------------------------------------------------

  static const String quickLinksTitle = 'Go to';

  /// Navigation only. Each of these carries **no figure**: the summary returns no
  /// Retailer, Product, shop, assignment or invitation count, so a number beside
  /// any of them would be one this screen invented.
  static const String quickLinksDescription =
      'The Vendor areas available to you. These are links, not figures.';

  static const String retailersLink = 'Retailers';
  static const String usersLink = 'Users';
  static const String rolesLink = 'Roles';
  static const String productsLink = 'Products';
  static const String auditLogsLink = 'Audit Logs';

  /// The spoken label for one quick link. Announces it as a destination rather
  /// than leaving a screen reader to infer it from an arrow glyph.
  static String quickLinkSemantics(String label) => 'Open $label';

  // -- spoken labels ---------------------------------------------------------

  /// The spoken form of one metric card: what it is, what the figure is, and
  /// which of the two scopes it belongs to — in that order, as one sentence.
  ///
  /// The scope is spoken rather than shown only as a chip, so the distinction
  /// survives for a reader who never sees the section heading it sits under.
  static String metricSemantics({
    required String label,
    required String value,
    required String scope,
    required String hint,
  }) => '$label: $value. $scope. $hint.';
}
