/// The four application roles, and the "no access" case.
///
/// Each value corresponds to a `kind` returned by the proposed
/// `public.get_my_portal_context()` RPC — see § 4.1 of
/// `docs/mobile-architecture-recommendation.md` in `salesreward-admin`.
///
/// > **A value of this enum is never proof of permission.**
/// >
/// > It exists so the app can decide which shell to build and which screens to
/// > offer. It gates no write, and it may never be constructed from a JWT claim,
/// > a local preference, or a string the user can influence. Every operation is
/// > authorized again in SQL, by a `SECURITY DEFINER` function that derives the
/// > caller from `auth.uid()` and accepts no user id. Hiding an affordance
/// > removes an accident; it never removes a capability.
enum AppRole {
  /// `kind = 'vendor'` — the Vendor Super Admin experience.
  vendorSuperAdmin(wireKind: 'vendor', displayName: 'Vendor Super Admin'),

  /// `kind = 'owner'` — the full Retailer portal.
  retailerOwner(wireKind: 'owner', displayName: 'Retailer Owner'),

  /// `kind = 'reader'` — the Retailer Manager's narrowed portal.
  ///
  /// The web calls this kind "reader" because it names *which read succeeded*,
  /// not who the caller claims to be. The mobile name matches the product's
  /// vocabulary; the wire value is unchanged.
  retailerManager(wireKind: 'reader', displayName: 'Retailer Manager'),

  /// `kind = 'submitter'` — receipt submission and personal history.
  salesStaff(wireKind: 'submitter', displayName: 'Sales Staff');

  const AppRole({required this.wireKind, required this.displayName});

  /// The `kind` string the backend returns. Used only to parse a server
  /// response — never to construct a role from anywhere else.
  final String wireKind;

  /// The role's name as the product speaks it. Presentation only.
  final String displayName;

  /// Parses a server-supplied `kind`.
  ///
  /// Returns null for `'none'` and for anything unrecognized — a fail-closed
  /// default, so a future backend value can never be mistaken for a role this
  /// build understands.
  static AppRole? fromWireKind(String? kind) {
    if (kind == null) {
      return null;
    }
    for (final AppRole role in AppRole.values) {
      if (role.wireKind == kind) {
        return role;
      }
    }
    return null;
  }
}

/// Where a resolved role came from, and therefore how far it may be trusted.
///
/// This distinction exists because backend role resolution is **not connected in
/// this milestone**: `public.get_my_portal_context()` does not exist yet. Rather
/// than fake a resolved role and let the rest of the app forget it was faked,
/// every resolved role carries its provenance, and any shell built from a
/// [RoleTrust.localPreview] role says so on screen.
enum RoleTrust {
  /// The role came from the backend, for this session, over an authenticated
  /// call. Still not permission — just a trustworthy hint about which shell to
  /// build.
  serverResolved,

  /// The role was chosen locally to preview the interface. It authorizes
  /// nothing whatsoever and must be visibly labelled wherever it is in effect.
  localPreview,
}

/// A role together with its provenance and, where the backend supplies one, the
/// tenant it belongs to.
final class ResolvedRole {
  const ResolvedRole({
    required this.role,
    required this.trust,
    this.retailerName,
  });

  /// A locally chosen role for previewing a shell. Never a grant.
  const ResolvedRole.preview(this.role)
    : trust = RoleTrust.localPreview,
      retailerName = null;

  final AppRole role;
  final RoleTrust trust;

  /// The retailer's display name, when the backend returns one. Null for the
  /// Vendor experience, and null for any preview.
  final String? retailerName;

  /// Whether this role may be relied on for anything beyond choosing a layout.
  ///
  /// Even when true the answer is "only for layout" — but a false value means
  /// the role is not even that.
  bool get isServerResolved => trust == RoleTrust.serverResolved;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolvedRole &&
          other.role == role &&
          other.trust == trust &&
          other.retailerName == retailerName;

  @override
  int get hashCode => Object.hash(role, trust, retailerName);
}
