import '../../domain/entities/vendor_user_detail.dart';
import '../../domain/entities/vendor_user_status.dart';
import '../../domain/entities/vendor_user_summary.dart';

/// A Vendor User response could not be understood.
///
/// Every branch that throws this is a branch that would otherwise have to guess,
/// and the only safe guess is none. The repository turns it into an operational
/// failure — **never** into an empty list, never into a fabricated user, never
/// into a fabricated role, and never into access denied.
final class VendorUserFormatException implements Exception {
  const VendorUserFormatException(this.reason);

  /// A short, developer-facing reason. Never rendered to a user, and never
  /// carrying a value read from the response.
  final String reason;

  @override
  String toString() => 'VendorUserFormatException: $reason';
}

/// The 8-4-4-4-12 hexadecimal shape of a UUID.
final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Whether [value] is shaped like a membership id.
///
/// Used before an id read off a route is put into a request, so a mistyped URL
/// cannot reach PostgREST as a `22P02` cast error and come back dressed as a
/// database outage.
bool isMembershipIdShaped(String value) => _uuid.hasMatch(value);

/// Parses `list_vendor_users()`.
abstract final class VendorUserSummaryParser {
  /// The rows, in the order the backend returned them.
  ///
  /// The SQL orders by `display_name, membership_id` — total, so two people
  /// sharing a name cannot swap places between requests. That order is preserved
  /// rather than re-sorted here; re-sorting would be a second, drifting
  /// definition of "the directory order", and the collation the database uses is
  /// not the one Dart's `compareTo` would apply.
  static List<VendorUserSummary> parseList(Object? raw) {
    return _rows(raw, 'users').map(parse).toList(growable: false);
  }

  static VendorUserSummary parse(Map<String, Object?> row) {
    return VendorUserSummary(
      membershipId: _uuidField(row['membership_id'], 'user.membership_id'),
      displayName: _requiredString(row['display_name'], 'user.display_name'),
      // A status token this build does not know degrades to `unknown`, which is
      // never active. A missing or blank one is a required value the response
      // did not supply, and _requiredString rejects it.
      profileStatus: VendorUserStatus.fromCode(
        _requiredString(row['profile_status'], 'user.profile_status'),
      ),
      membershipStatus: VendorUserStatus.fromCode(
        _requiredString(row['membership_status'], 'user.membership_status'),
      ),
      membershipCreatedAt: _requiredTimestamp(
        row['membership_created_at'],
        'user.membership_created_at',
      ),
      joinedAt: _optionalTimestamp(row['joined_at'], 'user.joined_at'),
      roleNames: _roleNames(row['role_names'], 'user.role_names'),
    );
  }
}

/// Parses `get_vendor_user_detail(uuid)`.
abstract final class VendorUserDetailParser {
  /// The single-row read. **Zero rows is a legitimate answer and yields null.**
  ///
  /// The backend returns zero rows for a nonexistent id, another Vendor's id, a
  /// Retailer-owned membership id and `null` alike — indistinguishably, so there
  /// is no existence oracle. This parser preserves that by having exactly one
  /// representation for all four, and by never turning any of them into an error
  /// the UI could word differently.
  static VendorUserDetail? parseSingle(Object? raw) {
    final List<Map<String, Object?>> rows = _rows(raw, 'user detail');
    if (rows.isEmpty) {
      return null;
    }
    if (rows.length > 1) {
      // The function filters on a primary key and the derived Vendor; more than
      // one row means the response is not the shape this build was written
      // against.
      throw const VendorUserFormatException(
        'user detail returned several rows',
      );
    }
    return parse(rows.first);
  }

  static VendorUserDetail parse(Map<String, Object?> row) {
    return VendorUserDetail(
      membershipId: _uuidField(row['membership_id'], 'detail.membership_id'),
      displayName: _requiredString(row['display_name'], 'detail.display_name'),
      profileStatus: VendorUserStatus.fromCode(
        _requiredString(row['profile_status'], 'detail.profile_status'),
      ),
      membershipStatus: VendorUserStatus.fromCode(
        _requiredString(row['membership_status'], 'detail.membership_status'),
      ),
      membershipCreatedAt: _requiredTimestamp(
        row['membership_created_at'],
        'detail.membership_created_at',
      ),
      joinedAt: _optionalTimestamp(row['joined_at'], 'detail.joined_at'),
      // The one column the list does not carry. Nullable for a live membership,
      // and never fabricated from the status.
      deactivatedAt: _optionalTimestamp(
        row['deactivated_at'],
        'detail.deactivated_at',
      ),
      roleNames: _roleNames(row['role_names'], 'detail.role_names'),
    );
  }
}

// ---------------------------------------------------------------------------
// Strict field readers
//
// Every one of these throws rather than substituting a default. A default here
// would be a value the backend never sent, presented as though it had — which is
// how a malformed response becomes fabricated data, and how an absent role
// becomes a privilege.
// ---------------------------------------------------------------------------

List<Map<String, Object?>> _rows(Object? raw, String what) {
  if (raw is! List) {
    throw VendorUserFormatException('$what is not a list');
  }
  return raw
      .map<Map<String, Object?>>((Object? element) {
        if (element is! Map) {
          throw VendorUserFormatException('$what row is not an object');
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
  throw VendorUserFormatException('$what missing or blank');
}

String _uuidField(Object? raw, String what) {
  final String value = _requiredString(raw, what);
  if (!isMembershipIdShaped(value)) {
    throw VendorUserFormatException('$what is not a UUID');
  }
  return value;
}

/// A `text[]` column that is **NOT NULL and may be empty**.
///
/// Three failures and one legitimate answer, and the distinction is the whole
/// point of this function:
///
/// * `null` → **format error.** The SQL coalesces the aggregate to `'{}'`, so a
///   null array is not "no roles" — it is a response this build was not written
///   against. Reading it as "no roles" would be a guess; reading it as anything
///   else would be worse.
/// * not a list, or an element that is not a non-blank string → format error.
/// * `[]` → **an empty list, preserved as such.** This person holds no active
///   role. It is never a default and never a Super Admin: an absent role is the
///   one place where a wrong guess would grant something.
///
/// Order is preserved exactly as the backend sent it (`role name, role id`).
/// Nothing is sorted, de-duplicated or filtered here — a `Set` would hide a
/// genuine backend duplication bug rather than prevent one.
List<String> _roleNames(Object? raw, String what) {
  if (raw is! List) {
    throw VendorUserFormatException('$what is not an array');
  }
  return raw
      .map<String>((Object? element) => _requiredString(element, '$what entry'))
      .toList(growable: false);
}

DateTime _requiredTimestamp(Object? raw, String what) {
  if (raw is! String) {
    throw VendorUserFormatException('$what is not a timestamp');
  }
  final DateTime? parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw VendorUserFormatException('$what is not a timestamp');
  }
  // Normalized to UTC on the way in, so the only place a timezone is applied is
  // where a value is formatted for display.
  return parsed.toUtc();
}

/// A nullable timestamp.
///
/// Absent and SQL NULL both yield null — a person who has not joined, or a
/// membership that has not been deactivated. A present value that cannot be
/// parsed is malformed, not "close enough", and is never quietly dropped to
/// null: that would turn an unreadable date into a confident "not joined yet".
DateTime? _optionalTimestamp(Object? raw, String what) {
  if (raw == null) {
    return null;
  }
  return _requiredTimestamp(raw, what);
}
