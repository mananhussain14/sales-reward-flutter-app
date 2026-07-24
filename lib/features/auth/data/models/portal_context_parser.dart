import '../../domain/entities/portal_context.dart';
import '../../domain/entities/portal_kind.dart';
import '../../domain/entities/retailer_capabilities.dart';

/// The response could not be understood.
///
/// Every branch that throws this is a branch that would otherwise have to guess,
/// and the only safe guess is none. A caller turns it into an operational
/// failure — **never** into a role, and never into access denied.
final class PortalContextFormatException implements Exception {
  const PortalContextFormatException(this.reason);

  /// A short, developer-facing reason. Never rendered to a user, and never
  /// carries a value read from the response.
  final String reason;

  @override
  String toString() => 'PortalContextFormatException: $reason';
}

/// Parses the `get_my_portal_context()` body into a [PortalContext].
///
/// ## Fail-safe rules
///
/// Every one of these exists so that a malformed or unfamiliar response can
/// never become a privileged role:
///
/// * a `context_version` that is not exactly [supportedPortalContextVersion]
///   → throw. A **higher** version means the backend is newer than this build
///   and the shape may have changed meaning; guessing is exactly what the
///   version field exists to prevent.
/// * an unknown or missing `portal_kind` → throw.
/// * a `vendor`/`retailer` block present but missing a required field, or
///   carrying a blank or non-UUID organization id → throw.
/// * `portal_kind` naming an experience whose block is absent → throw. Being
///   told to open the Vendor shell with no Vendor organization is incoherent,
///   and the routing decision must not be honoured in isolation.
/// * an unrecognized **extra** key → ignored. The contract is explicitly
///   additive; a new key must not break an old client.
/// * a missing **capability** → `false`. Capabilities are presentation hints,
///   so an unreadable one is simply not offered. This is the one place a
///   default is correct, because the default cannot widen anything: the
///   backend re-decides every operation regardless, and refusing to sign a user
///   in over a cosmetic hint would be disproportionate.
abstract final class PortalContextParser {
  /// Throws [PortalContextFormatException] if [raw] is not a context this build
  /// understands.
  static PortalContext parse(Object? raw) {
    final Map<String, Object?> root = _asMap(raw, 'response');

    final Object? rawVersion = root['context_version'];
    if (rawVersion is! int) {
      throw const PortalContextFormatException(
        'context_version missing or not an integer',
      );
    }
    if (rawVersion != supportedPortalContextVersion) {
      // Higher means a breaking change this build has not been written for;
      // lower means something older than the contract. Neither is guessable.
      throw const PortalContextFormatException('unsupported context_version');
    }

    final PortalKind? portalKind = PortalKind.tryParse(root['portal_kind']);
    if (portalKind == null) {
      throw const PortalContextFormatException(
        'portal_kind missing or unrecognized',
      );
    }

    final VendorContext? vendor = _parseVendor(root['vendor']);
    final RetailerContext? retailer = _parseRetailer(root['retailer']);

    _assertCoherent(portalKind, vendor: vendor, retailer: retailer);

    return PortalContext(
      contextVersion: rawVersion,
      portalKind: portalKind,
      vendor: vendor,
      retailer: retailer,
    );
  }

  /// The routing decision must be backed by the block it names.
  static void _assertCoherent(
    PortalKind portalKind, {
    required VendorContext? vendor,
    required RetailerContext? retailer,
  }) {
    switch (portalKind) {
      case PortalKind.vendorSuperAdmin:
        if (vendor == null) {
          throw const PortalContextFormatException(
            'portal_kind names the Vendor experience but vendor is null',
          );
        }
      case PortalKind.retailerOwner:
      case PortalKind.retailerManager:
      case PortalKind.salesStaff:
        if (retailer == null) {
          throw const PortalContextFormatException(
            'portal_kind names a Retailer experience but retailer is null',
          );
        }
        if (retailer.kind.portalKind != portalKind) {
          throw const PortalContextFormatException(
            'portal_kind disagrees with retailer.kind',
          );
        }
      case PortalKind.none:
        // NONE carries no blocks. The backend nulls both, and a stray block
        // here would mean the routing decision and the content disagree.
        if (vendor != null || retailer != null) {
          throw const PortalContextFormatException(
            'portal_kind is NONE but a context block is present',
          );
        }
    }
  }

  static VendorContext? _parseVendor(Object? raw) {
    if (raw == null) {
      return null;
    }
    final Map<String, Object?> map = _asMap(raw, 'vendor');
    return VendorContext(
      organizationId: _organizationId(map['organization_id'], 'vendor'),
      organizationName: _nonEmptyString(
        map['organization_name'],
        'vendor.organization_name',
      ),
    );
  }

  static RetailerContext? _parseRetailer(Object? raw) {
    if (raw == null) {
      return null;
    }
    final Map<String, Object?> map = _asMap(raw, 'retailer');

    final RetailerKind? kind = RetailerKind.tryParse(map['kind']);
    if (kind == null) {
      throw const PortalContextFormatException(
        'retailer.kind missing or unrecognized',
      );
    }

    return RetailerContext(
      kind: kind,
      organizationId: _organizationId(map['organization_id'], 'retailer'),
      organizationName: _nonEmptyString(
        map['organization_name'],
        'retailer.organization_name',
      ),
      capabilities: _parseCapabilities(map['capabilities']),
    );
  }

  /// Reads the capability block conservatively.
  ///
  /// A non-map block, or a missing/non-boolean flag, yields `false` for that
  /// flag rather than throwing. See the class doc for why this is the one safe
  /// default in the parser.
  static RetailerCapabilities _parseCapabilities(Object? raw) {
    if (raw is! Map) {
      return RetailerCapabilities.none;
    }
    bool flag(String key) => raw[key] == true;

    return RetailerCapabilities(
      viewRetailerOverview: flag('view_retailer_overview'),
      viewShops: flag('view_shops'),
      viewStaff: flag('view_staff'),
      manageStaff: flag('manage_staff'),
      assignStaffShops: flag('assign_staff_shops'),
      viewAssignedProducts: flag('view_assigned_products'),
      submitReceipts: flag('submit_receipts'),
    );
  }

  static Map<String, Object?> _asMap(Object? raw, String what) {
    if (raw is Map) {
      return raw.map<String, Object?>(
        (Object? key, Object? value) =>
            MapEntry<String, Object?>('$key', value),
      );
    }
    throw PortalContextFormatException('$what is not an object');
  }

  static String _nonEmptyString(Object? raw, String what) {
    if (raw is String && raw.trim().isNotEmpty) {
      return raw;
    }
    throw PortalContextFormatException('$what missing or blank');
  }

  /// Organization ids are UUIDs in the schema. Validating the shape keeps a
  /// malformed identifier from reaching a future request as though it were one.
  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static String _organizationId(Object? raw, String what) {
    final String value = _nonEmptyString(raw, '$what.organization_id');
    if (!_uuid.hasMatch(value)) {
      throw PortalContextFormatException('$what.organization_id is not a UUID');
    }
    return value;
  }
}
