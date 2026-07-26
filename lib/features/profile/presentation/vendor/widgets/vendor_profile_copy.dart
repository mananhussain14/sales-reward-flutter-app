/// Every user-facing sentence this feature renders, in one place.
///
/// Centralised for the same reason the Retailer, User, Role, Product, Audit and
/// Dashboard features centralise theirs — but here the stakes are unusual,
/// because **the labels say where each value came from**. Two trusted sources
/// meet on one screen: the company name from the authenticated session, and the
/// administrator's name and roles from a self-read. A label that blurred them
/// would let a reader take one for the other.
///
/// The rules these strings obey:
///
/// * **No raw backend text.** No Postgres message, SQLSTATE, table, column,
///   function, policy or permission name appears in any of them. A caller whose
///   role no longer holds `RBAC_READ` sees the same generic wording as a caller
///   who is not signed in.
/// * **Nothing is promised that does not exist.** `public.organizations` has
///   eight columns and none of them is a legal name, trading name, registration
///   identifier, tax identifier, website, business email, business phone or
///   postal address — there is no such column anywhere in the schema. So no
///   string here names one, not even as a disabled field or a dash.
/// * **The absence is product-shaped, not failure-shaped.**
///   [companyLimitationNote] says the details are *not configured yet*, which is
///   true. "Could not load" would be false and would invite a retry that could
///   not help.
/// * **No status is stated.** An authorized caller has an ACTIVE profile, an
///   ACTIVE membership and an ACTIVE organization by construction, so the backend
///   returns none of the three. Nothing here infers a badge from that.
/// * **Roles are named, never coded.** The backend returns `Vendor Super Admin`,
///   never `VENDOR_SUPER_ADMIN`, and nothing here maps one back to the other.
/// * **Nothing is editable, and nothing pretends to be.** There is no Edit, Save,
///   Change, Upload or Manage string anywhere in this feature, because this
///   product has no write path for company or profile data at all.
abstract final class VendorProfileCopy {
  // -- the page --------------------------------------------------------------

  static const String title = 'Company & profile';

  /// Says what the screen is and — in one clause — that it is read-only.
  static const String description =
      'A read-only view of the Vendor organization you administer, and of your '
      'own administrator account.';

  static const String refresh = 'Refresh';
  static const String refreshing = 'Refreshing…';

  /// Generic by design. A loading state must not name a person or an
  /// organization, because it must not leak what is being loaded.
  static const String loading = 'Loading company and profile';

  static const String staleTitle = 'This profile may be out of date';
  static const String staleBody =
      'We could not refresh your administrator profile just now. The details '
      'already loaded are still shown.';

  // -- the company section ---------------------------------------------------

  static const String companySectionTitle = 'Company';

  /// The scope label under the organization name.
  ///
  /// "Vendor organization" and not "Your company": the caller administers this
  /// organization, and the word the whole product uses for that relationship is
  /// Vendor.
  static const String companyScopeLabel = 'Vendor organization';

  /// Says where the name came from, in one line.
  ///
  /// Load-bearing rather than modest. The administrator details below it come
  /// from a different contract with a different authorization argument, and a
  /// reader who assumed one source for the whole card would be wrong.
  static const String companySourceNote =
      'Taken from your authenticated Vendor session.';

  /// The one honest sentence about everything this product does not store.
  ///
  /// Neutral and product-focused. It must not read as a failure: nothing failed,
  /// and there is no retry that could add a field the database has no column for.
  static const String companyLimitationNote =
      'Additional company details are not configured in SalesReward yet.';

  // -- the administrator section ---------------------------------------------

  static const String administratorSectionTitle = 'Signed-in administrator';

  /// Introduces the role list.
  ///
  /// "your current Vendor membership" is exact: the roles belong to the caller's
  /// membership in *this* organization, and a role the same person holds in
  /// another Vendor or in a Retailer organization cannot appear.
  static const String rolesTitle = 'Active roles';
  static const String rolesDescription =
      'Active roles for your current Vendor membership.';

  /// The defensive empty-array branch.
  ///
  /// Unreachable for an authorized caller — the ACTIVE Vendor Super Admin
  /// assignment that authorized them is always in the array — and rendered
  /// safely rather than crashing if it ever arrives. The same wording the web
  /// directory uses, so the two clients agree.
  static const String noRoles = 'No active role';

  // -- spoken labels ---------------------------------------------------------

  /// The spoken form of the company identity: what it is, then what it is called.
  static String companySemantics(String organizationName) =>
      '$companyScopeLabel: $organizationName. $companySourceNote';

  /// The spoken form of the administrator identity.
  static String administratorSemantics(String displayName) =>
      '$administratorSectionTitle: $displayName.';

  /// The spoken form of the whole role list — one sentence rather than N separate
  /// nodes, so a screen reader user is not made to walk several chips to learn
  /// one fact.
  static String rolesSemantics(List<String> roleNames) => roleNames.isEmpty
      ? '$rolesTitle: $noRoles.'
      : '$rolesTitle: ${roleNames.join(', ')}.';

  /// The spoken form of one role chip, for a reader navigating chip by chip.
  static String roleSemantics(String roleName) => 'Role: $roleName';
}
