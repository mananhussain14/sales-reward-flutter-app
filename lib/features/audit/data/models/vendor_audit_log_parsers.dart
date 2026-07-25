import '../../domain/entities/vendor_audit_actor_type.dart';
import '../../domain/entities/vendor_audit_log_entry.dart';

/// A Vendor Audit Log response could not be understood.
///
/// Every branch that throws this is a branch that would otherwise have to guess,
/// and on an audit surface the only safe guess is none. The repository turns it
/// into an operational failure — **never** into an empty history, never into a
/// fabricated event, never into a fabricated actor, never into `USER`, and never
/// into access denied.
final class VendorAuditLogFormatException implements Exception {
  const VendorAuditLogFormatException(this.reason);

  /// A short, developer-facing reason. Never rendered to a user, and never
  /// carrying a value read from the response.
  final String reason;

  @override
  String toString() => 'VendorAuditLogFormatException: $reason';
}

/// The 8-4-4-4-12 hexadecimal shape of a UUID.
final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Whether [value] is shaped like an audit log id.
///
/// Declared here rather than imported from the Retailer, Role or Product parsers
/// on purpose, matching those files' own reasoning: one feature reaching into
/// another's data layer for a regular expression is a dependency that outlives
/// the convenience, and this file must be readable as the whole of what this
/// feature parses.
bool isAuditLogIdShaped(String value) => _uuid.hasMatch(value);

/// Parses `list_vendor_audit_logs(...)`.
abstract final class VendorAuditLogEntryParser {
  /// The page, in the order the backend returned it.
  ///
  /// The SQL orders by `created_at desc, id desc` — total, because `id` is the
  /// primary key — so two events written inside one transaction cannot swap
  /// places between requests. That order is preserved rather than re-sorted
  /// here: re-sorting would be a second, drifting definition of "the history
  /// order", and it would immediately disagree with the web page showing the
  /// same rows. It is also the order the keyset cursor depends on, so a client
  /// that re-sorted would take its cursor from the wrong row.
  ///
  /// **One malformed row fails the whole page.** Dropping it would silently
  /// shorten a history with no sign that anything was missing — and an audit log
  /// that discards the records it cannot read is not an audit log. Worse, the
  /// cursor is built from the *last* row, so a dropped tail row would move the
  /// next page's boundary and skip real events.
  static List<VendorAuditLogEntry> parseList(Object? raw) {
    return _rows(raw, 'audit log page').map(parse).toList(growable: false);
  }

  static VendorAuditLogEntry parse(Map<String, Object?> row) {
    // NOT NULL in the contract, and the list key as well as half the cursor. A
    // malformed one would be put straight back into a `uuid` parameter on the
    // next page, where it would raise a cast error dressed as a database outage.
    final String auditLogId = _uuidField(row['audit_log_id'], 'audit_log_id');

    // NOT NULL, and the other half of the cursor. Kept exact and normalized to
    // UTC; the only place a time zone is applied is where a value is formatted.
    final DateTime occurredAt = _requiredTimestamp(
      row['occurred_at'],
      'occurred_at',
    );

    // NOT NULL with a non-empty CHECK on the column, and returned RAW. An
    // unfamiliar code is a forward-compatibility case, not a malformed
    // response — it is kept verbatim and rendered neutrally, never dropped and
    // never coerced to a code this build recognises.
    final String actionCode = _requiredString(
      row['action_code'],
      'action_code',
    );

    // NOT NULL with a non-empty CHECK, and returned RAW for the same reasons.
    final String entityType = _requiredString(
      row['entity_type'],
      'entity_type',
    );

    // NULLABLE, and null is an ordinary state rather than a fault: an
    // unrecognised entity type, a missing metadata key, a blank value and a
    // non-string value all produce it. A value of the wrong TYPE is malformed —
    // rendering `42` where a product name belongs would be presenting a response
    // this build cannot read as though it had understood it.
    final String? entityDisplayName = _optionalString(
      row['entity_display_name'],
      'entity_display_name',
    );

    // NOT NULL. A token this build does not know degrades to `unrecognized`,
    // which is never `user`. A missing or blank one is a required value the
    // response did not supply, and `_requiredString` rejects it.
    final VendorAuditActorType actorType = VendorAuditActorType.fromCode(
      _requiredString(row['actor_type'], 'actor_type'),
    );

    // NULLABLE, and constrained by the biconditional below.
    final String? actorDisplayName = _optionalString(
      row['actor_display_name'],
      'actor_display_name',
    );

    _assertActorNameMatchesType(actorType, actorDisplayName);

    return VendorAuditLogEntry(
      auditLogId: auditLogId,
      occurredAt: occurredAt,
      actionCode: actionCode,
      entityType: entityType,
      entityDisplayName: entityDisplayName,
      actorType: actorType,
      actorDisplayName: actorDisplayName,
      // No metadata field, no entity_id field, no actor_profile_id field, no
      // ip_address field and no user_agent field — the backend returns none of
      // them, and there is nowhere here to put one.
    );
  }
}

/// `actor_display_name` is non-null **if and only if** `actor_type` is `USER`.
///
/// The backend asserts this across the whole page in pgTAP rather than row by
/// row, and it is enforced again here so that every screen may rely on it
/// instead of re-deriving it.
///
/// Both directions are rejections rather than repairs, and each would be a
/// different lie:
///
/// * a `USER` with **no** name would render an attributed action as
///   unattributed, quietly erasing the one fact the row exists to record;
/// * a `SYSTEM` or `UNKNOWN` carrying a name would attribute an action to a
///   person the backend explicitly declined to name — for `UNKNOWN` that person
///   may belong to **another Vendor**, which is precisely the cross-tenant
///   disclosure the scoped SQL join exists to prevent.
///
/// An **unrecognised** actor type is held to the same rule. A name is meaningful
/// only against a known attribution rule, and this build has none for a token it
/// does not know; carrying one through would be asserting an attribution whose
/// meaning is unknown. A future actor type that follows the deployed
/// biconditional — no name outside `USER` — parses and renders neutrally, which
/// is the reachable forward-compatibility case.
void _assertActorNameMatchesType(VendorAuditActorType type, String? name) {
  if (type.carriesName && name == null) {
    throw const VendorAuditLogFormatException('actor_display_name missing');
  }
  if (!type.carriesName && name != null) {
    throw const VendorAuditLogFormatException('actor_display_name unexpected');
  }
}

// ---------------------------------------------------------------------------
// Strict field readers
//
// Every one of these throws rather than substituting a default. A default here
// would be a value the backend never sent, presented as though it had — which is
// how a malformed response becomes a fabricated audit event, how an unreadable
// actor becomes a named colleague, and how a broken timestamp becomes a moment
// nothing happened at.
// ---------------------------------------------------------------------------

List<Map<String, Object?>> _rows(Object? raw, String what) {
  if (raw is! List) {
    throw VendorAuditLogFormatException('$what is not a list');
  }
  return raw
      .map<Map<String, Object?>>((Object? element) {
        if (element is! Map) {
          throw VendorAuditLogFormatException('$what row is not an object');
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
  throw VendorAuditLogFormatException('$what missing or blank');
}

/// A nullable `text` column.
///
/// Absent and SQL NULL both yield null. A value of the **wrong type** is
/// malformed rather than "close enough". A present-but-blank string also yields
/// null: the SQL already collapses a blank snapshot to null with
/// `nullif(btrim(…), '')`, so a blank arriving here means the response is not
/// the shape this build expects — and treating whitespace as a name is exactly
/// how a screen comes to show an empty label where a fact belongs.
String? _optionalString(Object? raw, String what) {
  if (raw == null) {
    return null;
  }
  if (raw is! String) {
    throw VendorAuditLogFormatException('$what is not text');
  }
  return raw.trim().isEmpty ? null : raw;
}

String _uuidField(Object? raw, String what) {
  final String value = _requiredString(raw, what);
  if (!isAuditLogIdShaped(value)) {
    throw VendorAuditLogFormatException('$what is not a UUID');
  }
  return value;
}

DateTime _requiredTimestamp(Object? raw, String what) {
  if (raw is! String) {
    throw VendorAuditLogFormatException('$what is not a timestamp');
  }
  final DateTime? parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw VendorAuditLogFormatException('$what is not a timestamp');
  }
  // Normalized to UTC on the way in. The cursor is therefore always sent in the
  // same representation regardless of the device's zone, and the only place a
  // time zone is applied is where a value is formatted for display.
  return parsed.toUtc();
}
