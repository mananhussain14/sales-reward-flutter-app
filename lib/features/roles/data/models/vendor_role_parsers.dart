import '../../domain/entities/vendor_role_detail.dart';
import '../../domain/entities/vendor_role_permission.dart';
import '../../domain/entities/vendor_role_status.dart';
import '../../domain/entities/vendor_role_summary.dart';

/// A Vendor Role response could not be understood.
///
/// Every branch that throws this is a branch that would otherwise have to guess,
/// and the only safe guess is none. The repository turns it into an operational
/// failure — **never** into an empty catalogue, never into a fabricated role,
/// never into a fabricated count, never into an `ACTIVE` status, and never into
/// access denied.
final class VendorRoleFormatException implements Exception {
  const VendorRoleFormatException(this.reason);

  /// A short, developer-facing reason. Never rendered to a user, and never
  /// carrying a value read from the response.
  final String reason;

  @override
  String toString() => 'VendorRoleFormatException: $reason';
}

/// The 8-4-4-4-12 hexadecimal shape of a UUID.
final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Whether [value] is shaped like a role id.
///
/// Used before an id read off a route is put into a request, so a mistyped URL
/// cannot reach PostgREST as a `22P02` cast error and come back dressed as a
/// database outage.
bool isRoleIdShaped(String value) => _uuid.hasMatch(value);

/// Parses `list_vendor_roles()`.
abstract final class VendorRoleSummaryParser {
  /// The rows, in the order the backend returned them.
  ///
  /// The SQL orders by `role_name, role_id` — total, so two roles sharing a name
  /// cannot swap places between requests. That order is preserved rather than
  /// re-sorted here: re-sorting would be a second, drifting definition of "the
  /// catalogue order", and the collation the database uses is not the one Dart's
  /// `compareTo` would apply.
  static List<VendorRoleSummary> parseList(Object? raw) {
    return _rows(raw, 'role list').map(parse).toList(growable: false);
  }

  static VendorRoleSummary parse(Map<String, Object?> row) {
    return VendorRoleSummary(
      roleId: _uuidField(row['role_id'], 'role.role_id'),
      roleName: _requiredString(row['role_name'], 'role.role_name'),
      // Nullable in the deployed schema, and never fabricated: a role with no
      // description returns null, and null is what reaches the screen.
      description: _optionalString(
        row['role_description'],
        'role.role_description',
      ),
      // A token this build does not know degrades to `unknown`, which is never
      // active and never reports permissions as effective. A missing or blank
      // one is a required value the response did not supply, and
      // _requiredString rejects it.
      status: VendorRoleStatus.fromCode(
        _requiredString(row['role_status'], 'role.role_status'),
      ),
      createdAt: _requiredTimestamp(
        row['role_created_at'],
        'role.role_created_at',
      ),
      permissionCount: _requiredCount(
        row['permission_count'],
        'role.permission_count',
      ),
      assignedMemberCount: _requiredCount(
        row['assigned_member_count'],
        'role.assigned_member_count',
      ),
    );
  }
}

/// Parses `get_vendor_role_detail(uuid)`.
///
/// The projection is byte-identical to the list's, so this delegates to the same
/// field readers rather than restating them. A future column has to be added to
/// both reads or to neither, and there is exactly one place here for it to go.
abstract final class VendorRoleDetailParser {
  /// The single-row read. **Zero rows is a legitimate answer and yields null.**
  ///
  /// The backend returns zero rows for an unknown uuid, a uuid belonging to some
  /// other table and `null` alike — indistinguishably, so there is no existence
  /// oracle. This parser preserves that by having exactly one representation for
  /// all three, and by never turning any of them into an error the UI could word
  /// differently.
  static VendorRoleDetail? parseSingle(Object? raw) {
    final List<Map<String, Object?>> rows = _rows(raw, 'role detail');
    if (rows.isEmpty) {
      return null;
    }
    if (rows.length > 1) {
      // The function filters on a primary key; more than one row means the
      // response is not the shape this build was written against.
      throw const VendorRoleFormatException(
        'role detail returned several rows',
      );
    }
    return parse(rows.first);
  }

  static VendorRoleDetail parse(Map<String, Object?> row) =>
      VendorRoleSummaryParser.parse(row);
}

/// Parses `list_vendor_role_permissions(uuid)`.
abstract final class VendorRolePermissionParser {
  /// The mapped permissions, in the backend's `permission_name, permission id`
  /// order.
  ///
  /// Nothing here sorts, de-duplicates or filters. A `Set` would hide a genuine
  /// backend duplication bug rather than prevent one, and the ordering is
  /// already deterministic and total in SQL.
  ///
  /// **One malformed row fails the whole read.** Dropping it would silently
  /// shrink a list whose length the backend guarantees equals
  /// `permission_count`, and a screen showing five of six mappings with no sign
  /// that a sixth existed is worse than an honest retry.
  static List<VendorRolePermission> parseList(Object? raw) {
    return _rows(raw, 'role permissions').map(parse).toList(growable: false);
  }

  static VendorRolePermission parse(Map<String, Object?> row) {
    return VendorRolePermission(
      name: _requiredString(row['permission_name'], 'permission.name'),
      // Nullable, returned verbatim, never fabricated and never replaced by the
      // permission name.
      description: _optionalString(
        row['permission_description'],
        'permission.description',
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Strict field readers
//
// Every one of these throws rather than substituting a default. A default here
// would be a value the backend never sent, presented as though it had — which is
// how a malformed response becomes fabricated data, how an unreadable status
// becomes an ACTIVE role, and how a broken count becomes "this role grants
// nothing".
// ---------------------------------------------------------------------------

List<Map<String, Object?>> _rows(Object? raw, String what) {
  if (raw is! List) {
    throw VendorRoleFormatException('$what is not a list');
  }
  return raw
      .map<Map<String, Object?>>((Object? element) {
        if (element is! Map) {
          throw VendorRoleFormatException('$what row is not an object');
        }
        return element.map<String, Object?>(
          (Object? key, Object? value) =>
              MapEntry<String, Object?>('$key', value),
        );
      })
      .toList(growable: false);
}

String _requiredString(Object? raw, String what) {
  if (raw is String && raw.trim().isNotEmpty) {
    return raw;
  }
  throw VendorRoleFormatException('$what missing or blank');
}

/// A nullable `text` column.
///
/// Absent and SQL NULL both yield null — a role or a permission with no
/// description. A value of the **wrong type** is malformed rather than "close
/// enough": rendering `42` where a sentence belongs would be presenting a
/// response this build cannot read as though it had understood it.
///
/// A present-but-blank string also yields null, so a screen's "is there a
/// description?" test cannot be satisfied by whitespace.
String? _optionalString(Object? raw, String what) {
  if (raw == null) {
    return null;
  }
  if (raw is! String) {
    throw VendorRoleFormatException('$what is not text');
  }
  return raw.trim().isEmpty ? null : raw;
}

String _uuidField(Object? raw, String what) {
  final String value = _requiredString(raw, what);
  if (!isRoleIdShaped(value)) {
    throw VendorRoleFormatException('$what is not a UUID');
  }
  return value;
}

/// An `integer` count column.
///
/// Accepts an integer, and a `num` whose value is integral — JSON has one number
/// type and a transport is entitled to hand back `3.0`. A string is refused: a
/// numeric column arriving as text means the response is not the shape this
/// build was written against.
///
/// **A negative count is refused rather than clamped.** `count(*)` cannot be
/// negative, so a negative value is evidence the response is not the one this
/// build expects, and clamping it to zero would tell a Vendor "no permissions
/// mapped" on the strength of a number the backend never produced.
int _requiredCount(Object? raw, String what) {
  final int value;
  if (raw is int) {
    value = raw;
  } else if (raw is num && raw.isFinite && raw == raw.roundToDouble()) {
    value = raw.toInt();
  } else {
    throw VendorRoleFormatException('$what is not an integer');
  }

  if (value < 0) {
    throw VendorRoleFormatException('$what is negative');
  }
  return value;
}

DateTime _requiredTimestamp(Object? raw, String what) {
  if (raw is! String) {
    throw VendorRoleFormatException('$what is not a timestamp');
  }
  final DateTime? parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw VendorRoleFormatException('$what is not a timestamp');
  }
  // Normalized to UTC on the way in, so the only place a timezone is applied is
  // where a value is formatted for display.
  return parsed.toUtc();
}
