/// The lifecycle status of a role **definition**.
///
/// The deployed `public.roles` table constrains its `status` column with
/// `roles_status_allowed`, which permits exactly two values — `ACTIVE` and
/// `INACTIVE`. Both are read from the migration rather than assumed, and the
/// backend's pgTAP suite flips a role between them and watches the contract's
/// output follow.
///
/// ## This is the only status in the whole feature
///
/// A *permission* has no status. `public.permissions` has seven columns and
/// `public.role_permissions` has three, and neither carries one; no migration in
/// the backend repository ever adds one. An inactive assigned permission is not
/// merely unseeded — it is **unrepresentable**. So there is no
/// `VendorPermissionStatus` here, and there is no per-permission badge anywhere
/// in this feature.
///
/// ## Role status is what makes a mapped permission effective
///
/// `public.has_organization_permission()` carries no permission-status predicate
/// — there is no column to predicate on — but it does filter on
/// `r.status = 'ACTIVE'`. An [inactive] role therefore grants **nothing**,
/// however many permissions remain mapped to it. The mappings are still listed,
/// because that is what an administrator opened the screen to see; what makes
/// the list truthful is this value, rendered beside it.
///
/// [grantsMappedPermissions] is how a screen asks that question. It is a
/// positive test against [active] rather than `!= inactive`, so no future token
/// can arrive at "effective" by failing to match something else.
///
/// ## Why [unknown] exists, and what it may never do
///
/// A token this build does not recognise means the backend is newer than the
/// app. That is an additive change, so it degrades to [unknown] and renders as a
/// neutral "Unknown" badge rather than failing the read or dropping the role
/// from the catalogue — a Vendor must not lose sight of a role because its
/// status is unfamiliar.
///
/// [unknown] is **never** [active]: it is counted as neither active nor
/// inactive, it never reports that permissions are effective, and it never
/// carries the raw backend token to the screen. A **missing or blank** status is
/// a different thing entirely — a required value the response did not supply —
/// and the parser raises a format error for it.
enum VendorRoleStatus {
  /// Live. Its mapped permissions are the ones the backend will honour.
  active('ACTIVE'),

  /// Retired. Still listed and still openable — the detail screen is where a
  /// Vendor goes to understand a state — and its mappings are still shown, but
  /// they grant nothing.
  inactive('INACTIVE'),

  /// A value this build does not know. Displayed neutrally, and nothing more.
  unknown('');

  const VendorRoleStatus(this.code);

  /// The backend token, or the empty string for [unknown].
  final String code;

  /// Maps a backend token to a status, falling back to [unknown].
  ///
  /// Never throws: the caller has already established that a status string is
  /// present, and an unrecognised value is a forward-compatibility case rather
  /// than a malformed response.
  static VendorRoleStatus fromCode(String raw) {
    for (final VendorRoleStatus status in values) {
      if (status != unknown && status.code == raw) {
        return status;
      }
    }
    return unknown;
  }

  /// Whether this is the one status that means "active".
  bool get isActive => this == active;

  /// Whether the permissions mapped to a role in this state are currently
  /// **effective**.
  ///
  /// True for [active] alone. This is presentation input — it decides which
  /// sentence a screen shows — and never an authorization decision: the backend
  /// evaluates `has_organization_permission()` again on every call, and this
  /// client computes no access from a permission list.
  bool get grantsMappedPermissions => this == active;
}
