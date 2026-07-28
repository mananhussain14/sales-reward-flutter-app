/// The two roles a Retailer staff invitation may target.
///
/// ## A closed set, and it is closed on the backend first
///
/// `parseStaffInvitationRequest` in the shared delivery contract accepts
/// `RETAILER_MANAGER` and `SALES_STAFF` and refuses every other string, and
/// `reserve_retailer_staff_invitation()` resolves the code against the role
/// catalogue again in SQL under the caller's own token. So this enum is not the
/// authority — it exists so the form cannot express a role the contract has no
/// value for, and so the wire token is written down exactly once per role.
///
/// `RETAILER_OWNER` is deliberately absent. The deployed contract does not
/// accept it, so offering it would be a control whose only possible outcome is a
/// refusal.
enum RetailerStaffInvitationRole {
  /// A Retailer Manager. Carries **no** shops, ever.
  retailerManager('RETAILER_MANAGER', 'Retailer Manager'),

  /// A Sales Staff member. Carries **at least one** shop.
  salesStaff('SALES_STAFF', 'Sales Staff');

  const RetailerStaffInvitationRole(this.code, this.label);

  /// The exact wire token. Sent verbatim as `roleCode`; never shown.
  final String code;

  /// The user-facing name. Shown; never sent.
  final String label;

  /// Whether an invitation for this role carries shop ids.
  ///
  /// A single positive test, so a role added later cannot arrive at "carries
  /// shops" by failing to match something else. The rule it names is the
  /// contract's own: a Manager submitting any shop is
  /// `INVALID_ROLE_SHOP_COMBINATION`, and so is Sales Staff submitting none.
  bool get carriesShops => this == salesStaff;
}
