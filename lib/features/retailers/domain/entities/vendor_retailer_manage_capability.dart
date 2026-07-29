/// Whether this caller holds `RETAILERS_MANAGE`, as the **database** answered.
///
/// ## Three states, and the last two are kept apart deliberately
///
/// [denied] is a definite "no" from the database. [unavailable] is "we could not
/// ask". Only one of them is a fact about the caller, so collapsing them would
/// mean reporting a service problem as a refusal of somebody's rights.
///
/// They nevertheless produce the **same** interface: the control is hidden for
/// both, because the only safe response to not knowing is to offer nothing.
///
/// ## This is a presentation probe. It is never an enforcement boundary.
///
/// A [confirmed] here permits a control to *render*.
/// `public.set_vendor_retailer_status()` re-derives the acting Vendor from
/// `auth.uid()` and re-proves the permission through
/// `has_organization_permission()` under its own row locks, regardless of what
/// any screen decided. Nothing downstream may treat a [confirmed] as permission
/// to write, and nothing may persist one.
enum VendorRetailerManageCapability {
  /// The database said yes.
  confirmed,

  /// The database said no — including an unauthenticated or unauthorized
  /// caller, who has no Vendor context to hold a permission in.
  denied,

  /// The question could not be asked, or the answer could not be read. **Not a
  /// fact about the caller.**
  unavailable;

  /// Whether the capability has been positively confirmed.
  ///
  /// ## Written as positive equality, and that is the whole point
  ///
  /// This is `== confirmed`, not `!= denied`. An exclusion list fails **open**
  /// the moment a member is added to this enum: a future `pending` would satisfy
  /// "not denied" and the control would render for a caller who may not use it.
  ///
  /// Positive equality fails **closed** for every such case without being
  /// edited, which is why every call site in this feature goes through here
  /// rather than comparing members itself.
  bool get isConfirmed => this == confirmed;
}
