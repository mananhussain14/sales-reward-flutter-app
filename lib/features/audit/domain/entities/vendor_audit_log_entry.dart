import 'package:equatable/equatable.dart';

import 'vendor_audit_actor_type.dart';

/// One recorded administrative event in the calling Vendor's history.
///
/// The seven columns `public.list_vendor_audit_logs(...)` returns, and nothing
/// else. The list is already tenant-scoped and privacy-filtered in SQL, so
/// there is no organization id here to scope it again with, and no client-side
/// predicate could make it narrower.
///
/// ## What is deliberately absent
///
/// The backend withholds each of these, and the entity has nowhere to put one:
///
/// * **`metadata`** — unrestricted `jsonb`. Only five whitelisted *name* keys
///   are read from it in SQL, each guarded to `jsonb_typeof = 'string'`, and the
///   extracted value arrives as [entityDisplayName]. The raw object is never
///   returned, never partially returned, and never returned for an unrecognised
///   entity type.
/// * **`entity_id`** — opaque, and for the two invitation types it identifies a
///   row that also carries an email and a token hash. There is no entity
///   navigation in this milestone, so it would be an unused identifier of a
///   sensitive row travelling to a phone.
/// * **`actor_profile_id`** — `public.profiles.id` **is the auth user id**, so
///   returning it would return an auth identifier under a friendlier name. The
///   actor travels as a type and, at most, a name.
/// * **`ip_address` and `user_agent`** — never selected by the function at all,
///   not merely never rendered.
/// * **`organization_id`** — an id in a payload is one a form could echo back
///   as authorization.
///
/// ## The raw codes are kept, and the labels are not
///
/// [actionCode] and [entityType] are the exact stored strings. There is no
/// label column to return, because no trusted mapping exists in the schema:
/// both columns are plain `text` with only a non-empty check — no enum, no
/// lookup table, no reference data.
///
/// Friendly wording is therefore a **presentation** concern and lives in
/// `vendor_audit_log_labels.dart`. Keeping the raw code on the entity is what
/// lets an unfamiliar code stay visible and stay honest, and no security,
/// navigation or visibility decision is ever made from a label.
///
/// ## There is no outcome field, and none is invented
///
/// `public.audit_logs` has no success/failure column. Outcome is encoded in the
/// action itself where it is recorded at all — `STAFF_INVITATION_DELIVERY_FAILED`
/// is the only failure event this schema writes — and a failed *authorization*
/// attempt produces no row anywhere, because an audit row is written inside the
/// transaction that succeeded.
final class VendorAuditLogEntry extends Equatable {
  const VendorAuditLogEntry({
    required this.auditLogId,
    required this.occurredAt,
    required this.actionCode,
    required this.entityType,
    required this.entityDisplayName,
    required this.actorType,
    required this.actorDisplayName,
  });

  /// `audit_logs.id`. The list key **and** half of the keyset cursor.
  ///
  /// Never rendered as a label: it is an address, not a fact about the event.
  final String auditLogId;

  /// `audit_logs.created_at`, exact and in UTC. The other half of the cursor.
  ///
  /// Kept as a [DateTime] rather than a formatted string so the cursor is the
  /// value the backend sent and the screen's local-time rendering is applied in
  /// exactly one place.
  final DateTime occurredAt;

  /// The raw stored action, e.g. `PRODUCT_CREATED`. Non-null, non-blank.
  final String actionCode;

  /// The raw stored entity type, e.g. `VENDOR_PRODUCT`. Non-null, non-blank.
  final String entityType;

  /// The **historical name snapshot** of the affected thing, or null.
  ///
  /// Read in SQL from the metadata key whitelisted for [entityType], so it is
  /// what the thing was called *at the moment of the event* — a deleted entity
  /// still has a name, and a renamed one keeps its old one. It is not a live
  /// join, which is why it cannot answer "does this id still exist" for anybody.
  ///
  /// Null is a normal state, never an error and never a reason to hide the row:
  /// an unrecognised entity type, a missing key, a blank value and a non-string
  /// value all produce it.
  final String? entityDisplayName;

  /// How far the backend could attribute this event. See
  /// [VendorAuditActorType] — in particular why `SYSTEM` is not a claim that a
  /// system process acted.
  final VendorAuditActorType actorType;

  /// The actor's name, non-null **iff** [actorType] is
  /// [VendorAuditActorType.user].
  ///
  /// That biconditional is asserted across the whole page in the backend's
  /// pgTAP suite and enforced again by this client's parser, so a screen may
  /// rely on it rather than re-deriving it.
  final String? actorDisplayName;

  /// Whether the affected thing carries a historical name.
  bool get hasEntityDisplayName => entityDisplayName != null;

  @override
  List<Object?> get props => <Object?>[
    auditLogId,
    occurredAt,
    actionCode,
    entityType,
    entityDisplayName,
    actorType,
    actorDisplayName,
  ];
}

/// The position a page of older activity continues from.
///
/// **Both halves, always, and both from the same row.** `created_at` defaults to
/// `now()`, which in PostgreSQL is the *transaction* timestamp, so two audit
/// rows written inside one transaction carry byte-identical timestamps. A
/// timestamp-only cursor over a tied pair either re-emits both rows on the next
/// page or skips both — there is no third outcome. `id` is the primary key, so
/// `(created_at, id)` is unique, the ordering is total, and the page boundary
/// falls at exactly one place.
///
/// The backend refuses a **half** cursor with `22023` rather than silently
/// completing it with a default, because quietly treating one as "the newest
/// page" would present a rewound list as a continuation — which is how a
/// paginating client loses rows without noticing. This type makes a half cursor
/// unrepresentable, so that refusal is unreachable from here.
///
/// ## It is ordering data, never authority
///
/// The cursor is applied **after** the tenant predicate in SQL, never instead of
/// it. A cursor copied from another Vendor's page — or invented outright — moves
/// the window within the caller's **own** history and can never reach across the
/// tenant boundary. This client neither invents nor alters one: every cursor it
/// sends is the `occurred_at` and `audit_log_id` of the final row of the page it
/// is continuing from.
typedef VendorAuditLogCursor = ({DateTime occurredAt, String auditLogId});

/// The cursor that continues from [entry].
VendorAuditLogCursor cursorFrom(VendorAuditLogEntry entry) =>
    (occurredAt: entry.occurredAt, auditLogId: entry.auditLogId);
