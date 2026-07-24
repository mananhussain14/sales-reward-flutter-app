/// Which experience the backend has decided this caller should open.
///
/// The wire values are the `portal_kind` literals returned by
/// `public.get_my_portal_context()`. They are the role codes from
/// `public.roles.code`, so they are already the vocabulary the rest of the
/// schema uses — this enum does not invent a parallel one.
///
/// > **A value of this enum is never proof of permission.**
/// >
/// > It exists so the app can decide which shell to build. It gates no write,
/// > and it may only ever be constructed by parsing an authenticated response
/// > from the backend — never from user input, an email address, profile
/// > metadata, a JWT claim, or local storage. Every operation is authorized
/// > again in SQL by a `SECURITY DEFINER` function that derives the caller from
/// > `auth.uid()` and accepts no arguments.
///
/// The backend applies **vendor-first precedence**: a caller who holds both a
/// Vendor and a Retailer role receives [vendorSuperAdmin] here, while their
/// Retailer block is still returned separately so the Retailer portal stays
/// reachable without a second resolution.
enum PortalKind {
  vendorSuperAdmin(
    wireValue: 'VENDOR_SUPER_ADMIN',
    displayName: 'Vendor Super Admin',
  ),
  retailerOwner(wireValue: 'RETAILER_OWNER', displayName: 'Retailer Owner'),
  retailerManager(
    wireValue: 'RETAILER_MANAGER',
    displayName: 'Retailer Manager',
  ),
  salesStaff(wireValue: 'SALES_STAFF', displayName: 'Sales Staff'),

  /// The explicit absence of an experience.
  ///
  /// Deliberately the **same** answer for every unauthorized case — signed out,
  /// no profile, suspended profile, suspended membership, inactive role, a
  /// Vendor-shaped account with no Retailer role, and the ambiguous
  /// multi-Retailer case are all `NONE`. The backend never says why, so this
  /// value carries no reason either.
  ///
  /// It is a **decision**, not a failure. A thrown RPC error is a different
  /// thing entirely and must never be collapsed into this.
  none(wireValue: 'NONE', displayName: 'No access');

  const PortalKind({required this.wireValue, required this.displayName});

  /// The literal the backend sends.
  final String wireValue;

  /// The name the product speaks. Presentation only.
  final String displayName;

  /// Whether this kind has a role shell to open.
  bool get hasShell => this != PortalKind.none;

  /// Parses a backend `portal_kind`.
  ///
  /// Returns null for anything unrecognized — including a future kind this
  /// build has never heard of. Callers must treat null as a **parse failure**,
  /// never as a default: silently mapping an unknown literal onto a role would
  /// be the one bug in this file that could escalate privilege.
  static PortalKind? tryParse(Object? value) {
    if (value is! String) {
      return null;
    }
    for (final PortalKind kind in PortalKind.values) {
      if (kind.wireValue == value) {
        return kind;
      }
    }
    return null;
  }
}

/// The kind recorded inside the `retailer` block.
///
/// A narrower set than [PortalKind]: the backend only ever reports
/// `RETAILER_OWNER`, `RETAILER_MANAGER` or `SALES_STAFF` there. Modelling it
/// separately means a `RetailerContext` carrying `VENDOR_SUPER_ADMIN` or `NONE`
/// is unrepresentable rather than merely unexpected.
enum RetailerKind {
  owner(wireValue: 'RETAILER_OWNER', portalKind: PortalKind.retailerOwner),
  manager(
    wireValue: 'RETAILER_MANAGER',
    portalKind: PortalKind.retailerManager,
  ),
  salesStaff(wireValue: 'SALES_STAFF', portalKind: PortalKind.salesStaff);

  const RetailerKind({required this.wireValue, required this.portalKind});

  final String wireValue;

  /// The [PortalKind] this retailer kind corresponds to, so a shell can be
  /// opened from the retailer block directly.
  final PortalKind portalKind;

  /// Parses a backend `retailer.kind`. Null means unrecognized — a parse
  /// failure, never a default.
  static RetailerKind? tryParse(Object? value) {
    if (value is! String) {
      return null;
    }
    for (final RetailerKind kind in RetailerKind.values) {
      if (kind.wireValue == value) {
        return kind;
      }
    }
    return null;
  }
}
