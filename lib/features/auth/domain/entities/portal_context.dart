import 'package:equatable/equatable.dart';

import 'portal_kind.dart';
import 'retailer_capabilities.dart';

/// The `context_version` this build understands.
///
/// The backend increments it **only on a breaking change** — a key removed,
/// renamed, or given a new meaning. Adding a key does not increment it, because
/// adding a key breaks nobody.
///
/// A client must therefore treat an unrecognized (higher) version as "this
/// backend is newer than me" and fall back conservatively rather than guessing
/// at a shape it has never seen. Parsing rejects anything that is not exactly
/// this value, which surfaces as an operational failure with a retry — never as
/// a role, and never as access denied.
const int supportedPortalContextVersion = 1;

/// The Vendor organization the caller administers.
final class VendorContext extends Equatable {
  const VendorContext({
    required this.organizationId,
    required this.organizationName,
  });

  /// Always an organization the caller is an ACTIVE member of — the backend has
  /// no parameter through which another could be named.
  final String organizationId;

  final String organizationName;

  @override
  List<Object?> get props => <Object?>[organizationId, organizationName];
}

/// The Retailer organization the caller belongs to, and what its portal may
/// show them.
final class RetailerContext extends Equatable {
  const RetailerContext({
    required this.kind,
    required this.organizationId,
    required this.organizationName,
    required this.capabilities,
  });

  final RetailerKind kind;
  final String organizationId;
  final String organizationName;

  /// Presentation hints only. See [RetailerCapabilities].
  final RetailerCapabilities capabilities;

  @override
  List<Object?> get props => <Object?>[
    kind,
    organizationId,
    organizationName,
    capabilities,
  ];
}

/// The complete answer to "which experience is this caller in?".
///
/// Produced by exactly one authenticated call to
/// `public.get_my_portal_context()`, which takes **zero arguments** and derives
/// identity from `auth.uid()`.
///
/// ## Why both blocks exist
///
/// [portalKind] is the routing decision and applies vendor-first precedence.
/// [vendor] and [retailer] are resolved **independently**, and both are
/// populated for a caller who genuinely holds both — so a shell already inside
/// the Retailer portal can read [retailer] directly without a second
/// resolution, exactly as the web's `getRetailerPortalAccess()` does.
///
/// ## What this is not
///
/// It is not a capability grant, a permission set, or a token. It is a
/// presentation and navigation input whose every claim the backend will
/// re-decide on the next call.
final class PortalContext extends Equatable {
  const PortalContext({
    required this.contextVersion,
    required this.portalKind,
    this.vendor,
    this.retailer,
  });

  /// The denied context: a real, successful answer whose content is "nothing".
  static const PortalContext denied = PortalContext(
    contextVersion: supportedPortalContextVersion,
    portalKind: PortalKind.none,
  );

  final int contextVersion;

  /// Where the application should open.
  final PortalKind portalKind;

  /// Null unless the caller is an active Vendor Super Admin.
  final VendorContext? vendor;

  /// Null unless the caller holds a Retailer role.
  final RetailerContext? retailer;

  /// True when the backend answered `NONE` — a decision, not a failure.
  bool get isDenied => portalKind == PortalKind.none;

  /// The organization name to caption the shell with, or null when the backend
  /// supplied none.
  ///
  /// Deliberately null rather than a placeholder: the web omits the name rather
  /// than fabricating one, and a Retailer Manager genuinely cannot read their
  /// own organization's name through the owner-filtered context RPC.
  String? get organizationName => switch (portalKind) {
    PortalKind.vendorSuperAdmin => vendor?.organizationName,
    PortalKind.retailerOwner ||
    PortalKind.retailerManager ||
    PortalKind.salesStaff => retailer?.organizationName,
    PortalKind.none => null,
  };

  /// The capabilities in effect for the Retailer portal, or
  /// [RetailerCapabilities.none] when there is no retailer block.
  ///
  /// Never null, so a caller cannot accidentally treat "unknown" as "allowed".
  RetailerCapabilities get capabilities =>
      retailer?.capabilities ?? RetailerCapabilities.none;

  @override
  List<Object?> get props => <Object?>[
    contextVersion,
    portalKind,
    vendor,
    retailer,
  ];
}
