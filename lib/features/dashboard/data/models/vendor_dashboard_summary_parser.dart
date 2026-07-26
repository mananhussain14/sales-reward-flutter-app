import '../../domain/entities/vendor_dashboard_summary.dart';

/// A Vendor Dashboard summary response could not be understood.
///
/// Every branch that throws this is a branch that would otherwise have to guess,
/// and on a metrics surface the only safe guess is none. The repository turns it
/// into an operational failure — **never** into a summary of zeros, never into a
/// partially populated summary, and never into access denied.
///
/// Zero is the load-bearing case. `0` is a real, reachable answer for both
/// Vendor-scoped counts, so a parser that substituted it for a field it could not
/// read would tell a Vendor "you have no members and nothing has ever happened
/// here" on the strength of a response this build did not understand.
final class VendorDashboardFormatException implements Exception {
  const VendorDashboardFormatException(this.reason);

  /// A short, developer-facing reason. Never rendered to a user, and never
  /// carrying a value read from the response.
  final String reason;

  @override
  String toString() => 'VendorDashboardFormatException: $reason';
}

/// The largest count this build will render.
///
/// `2^53 - 1`, the largest integer a JavaScript number represents exactly — which
/// is what a Dart `int` compiles to on Flutter web. A `bigint` above it has
/// already lost precision inside `JSON.parse` before any Dart code runs, so no
/// amount of care here could recover it.
///
/// A value above this is therefore **rejected as malformed rather than
/// rendered**, and rejected on every platform including the VM, where it would in
/// fact fit. Two clients quietly disagreeing about the same figure is worse than
/// one honest "could not load this": a count is only useful if it is the same
/// number the web shows.
///
/// It is unreachable in practice — nine quadrillion audit rows — and is recorded
/// as a known limitation rather than left as an assumption.
const int maxSafeVendorDashboardCount = 9007199254740991;

/// Parses `get_vendor_admin_dashboard_summary()`.
///
/// ## Exactly one row, and the count is checked rather than assumed
///
/// An authorized caller always receives exactly one row — structurally, because
/// the function body is a `select` with no from-clause. Zero rows and two rows
/// are therefore both impossible against the deployed contract, which is
/// precisely why both are **rejected** here instead of being tolerated: either
/// one means this build and the deployed function disagree, and the honest
/// response to that is an outage the user can retry past.
///
/// Taking "the first row" of a two-row answer would render figures whose
/// provenance this build cannot explain; treating zero rows as an empty summary
/// would render four zeros the backend never sent.
abstract final class VendorDashboardSummaryParser {
  /// The single summary row.
  ///
  /// The body is a JSON **array** — PostgREST renders a set-returning function as
  /// one — carrying exactly one object of four counts.
  static VendorDashboardSummary parse(Object? raw) {
    if (raw is! List) {
      throw const VendorDashboardFormatException('summary is not a list');
    }
    if (raw.length != 1) {
      // Both directions are the same statement: the contract guarantees one row
      // for an authorized caller, so anything else is a contract mismatch rather
      // than a state to render.
      throw VendorDashboardFormatException(
        'summary must carry exactly one row, not ${raw.length}',
      );
    }

    final Object? first = raw.single;
    if (first is! Map) {
      throw const VendorDashboardFormatException(
        'summary row is not an object',
      );
    }
    final Map<String, Object?> row = first.map<String, Object?>(
      (Object? key, Object? value) => MapEntry<String, Object?>('$key', value),
    );

    // All four are read before anything is constructed, so a malformed fourth
    // field fails the whole summary rather than leaving three fields rendered
    // beside a fabricated one. The four counts are one snapshot; there is no
    // partial summary to emit.
    final int activeMemberCount = _requiredCount(
      row['active_member_count'],
      'active_member_count',
    );
    final int catalogActiveRoleCount = _requiredCount(
      row['catalog_active_role_count'],
      'catalog_active_role_count',
    );
    final int catalogPermissionCount = _requiredCount(
      row['catalog_permission_count'],
      'catalog_permission_count',
    );
    final int auditEventCount = _requiredCount(
      row['audit_event_count'],
      'audit_event_count',
    );

    return VendorDashboardSummary(
      activeMemberCount: activeMemberCount,
      catalogActiveRoleCount: catalogActiveRoleCount,
      catalogPermissionCount: catalogPermissionCount,
      auditEventCount: auditEventCount,
      // No organization id, no organization name, no status, no timestamp and no
      // permission code — the contract returns none of them, and there is nowhere
      // here to put one.
    );
  }
}

// ---------------------------------------------------------------------------
// The strict field reader
//
// It throws rather than substituting a default. A default here would be a value
// the backend never sent, presented as though it had — which on this screen is
// how a missing field becomes "no active members" and a malformed one becomes
// "nothing has ever happened in this organization".
// ---------------------------------------------------------------------------

/// A `bigint` count column: `NOT NULL`, and non-negative by construction.
///
/// ## Why `int` alone, and no `num` conversion
///
/// The Role and Product parsers accept a `num` whose value is integral, on the
/// reasoning that JSON has one number type and a transport is entitled to hand
/// back `3.0`. That is sound for the `integer` columns those features read, whose
/// values are small.
///
/// It is **not** sound for `bigint`. Accepting a `double` means normalising it
/// through floating-point arithmetic, and a `double` large enough to matter has
/// already been rounded — so the conversion would launder a wrong number into a
/// confident one. This reader therefore takes an `int` and nothing else, and
/// bounds it at [maxSafeVendorDashboardCount] so the same value is either
/// rendered identically on the VM and on the web or rendered on neither.
///
/// On Flutter web every whole JavaScript number *is* an `int`, so a well-formed
/// response parses there exactly as it does on the VM.
///
/// **A negative count is refused rather than clamped.** `count(*)` cannot be
/// negative, so a negative value is evidence the response is not the one this
/// build expects; clamping it to zero would state a fact the backend never sent.
/// A **string** is refused for the same reason: a numeric column arriving as text
/// means the response is not this shape.
int _requiredCount(Object? raw, String what) {
  if (raw is! int) {
    throw VendorDashboardFormatException('$what is not an integer');
  }
  if (raw < 0) {
    throw VendorDashboardFormatException('$what is negative');
  }
  if (raw > maxSafeVendorDashboardCount) {
    throw VendorDashboardFormatException(
      '$what exceeds the exact integer range',
    );
  }
  return raw;
}
