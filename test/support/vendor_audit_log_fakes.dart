import 'dart:async';

import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/core/result/read_result.dart';
import 'package:sale_reward/features/audit/data/datasources/vendor_audit_log_rpc_data_source.dart';
import 'package:sale_reward/features/audit/domain/entities/vendor_audit_actor_type.dart';
import 'package:sale_reward/features/audit/domain/entities/vendor_audit_log_entry.dart';
import 'package:sale_reward/features/audit/domain/repositories/vendor_audit_log_repository.dart';

/// A hand-written [VendorAuditLogRepository] fake.
///
/// Hand-written rather than mocked because these tests care about *what was
/// sent* as much as what came back: [requestedCursors] is how a test proves that
/// the cursor is both halves of the final loaded row and nothing else, and that
/// a refresh sends no cursor at all.
///
/// By default it pages [history] — the newest [pageSize] rows, then the rows
/// strictly older than the supplied cursor — so a test can walk a real
/// multi-page history without scripting each answer.
class FakeVendorAuditLogRepository implements VendorAuditLogRepository {
  /// The whole history this fake will page through, newest first.
  List<VendorAuditLogEntry> history = List<VendorAuditLogEntry>.of(
    auditFirstPage,
  );

  /// The page size the fake honours.
  ///
  /// Pinned to the client's own fixed page size rather than made adjustable, and
  /// that is deliberate: the client decides "there is nothing older" from a page
  /// **shorter than the size it asked for**, so a fake that answered short pages
  /// by configuration would report the end of the history on its very first
  /// read and no pagination test could reach a second page at all.
  ///
  /// A test that wants several pages therefore supplies a longer [history] —
  /// see [auditHistoryOf] — which is also what exercises the real 50-row
  /// boundary rather than a miniature of it.
  static const int pageSize = vendorAuditLogPageSize;

  /// When set, **every** call answers this whatever was asked for — how a test
  /// scripts a failure or an empty page.
  ReadResult<List<VendorAuditLogEntry>>? result;

  /// One entry per call: null for a newest-page read, the pair for an older-page
  /// read. Order preserved.
  final List<VendorAuditLogCursor?> requestedCursors =
      <VendorAuditLogCursor?>[];

  int get callCount => requestedCursors.length;

  /// Reads that sent no cursor — the first page and every refresh.
  int get newestCallCount =>
      requestedCursors.where((VendorAuditLogCursor? c) => c == null).length;

  /// Reads that sent a cursor.
  List<VendorAuditLogCursor> get olderCursors => requestedCursors
      .whereType<VendorAuditLogCursor>()
      .toList(growable: false);

  /// When true, every call stays pending until [complete] is called — so "a
  /// second refresh while one is in flight" and "a stale answer arriving after a
  /// session change" are deterministic rather than a sleep-and-hope.
  bool manual = false;
  final List<Completer<ReadResult<List<VendorAuditLogEntry>>>> _pending =
      <Completer<ReadResult<List<VendorAuditLogEntry>>>>[];

  int get pendingCount => _pending.length;

  /// Completes the oldest pending call.
  void complete([ReadResult<List<VendorAuditLogEntry>>? override]) =>
      completeAt(0, override);

  /// Completes a pending call **out of order**, so a test can make an older
  /// request answer after a newer one — the stale-response race the request
  /// token exists to close. [index] is into the pending queue, oldest first.
  void completeAt(
    int index, [
    ReadResult<List<VendorAuditLogEntry>>? override,
  ]) {
    final Completer<ReadResult<List<VendorAuditLogEntry>>> completer = _pending
        .removeAt(index);
    completer.complete(override ?? result ?? _pageFor(requestedCursors[index]));
  }

  @override
  Future<ReadResult<List<VendorAuditLogEntry>>> auditLogs({
    VendorAuditLogCursor? before,
  }) {
    requestedCursors.add(before);
    if (manual) {
      final Completer<ReadResult<List<VendorAuditLogEntry>>> completer =
          Completer<ReadResult<List<VendorAuditLogEntry>>>();
      _pending.add(completer);
      return completer.future;
    }
    return Future<ReadResult<List<VendorAuditLogEntry>>>.value(
      result ?? _pageFor(before),
    );
  }

  /// One keyset page of [history], the way the backend produces it: the rows
  /// strictly older than the cursor, capped at [pageSize].
  ReadResult<List<VendorAuditLogEntry>> _pageFor(VendorAuditLogCursor? before) {
    Iterable<VendorAuditLogEntry> rows = history;

    if (before != null) {
      final int index = history.indexWhere(
        (VendorAuditLogEntry e) => e.auditLogId == before.auditLogId,
      );
      // A cursor naming no row this fake holds positions past everything, which
      // is what the backend does too: it moves the window, it grants nothing.
      rows = index < 0
          ? const <VendorAuditLogEntry>[]
          : history.skip(index + 1);
    }

    return ReadSuccess<List<VendorAuditLogEntry>>(
      rows.take(pageSize).toList(growable: false),
    );
  }
}

// ---------------------------------------------------------------------------
// Fixtures
//
// Invented names, codes and ids. Nothing here is a real identifier from any
// environment. The shape follows the deployed contract:
//
//   * a USER event with a name and a whitelisted entity name — the ordinary row;
//   * an UNKNOWN event, so the neutral wording has something to render;
//   * a SYSTEM event, the one genuinely ambiguous state;
//   * an event whose entity carries NO name snapshot, so a null renders honestly
//     rather than being filled in;
//   * an event with an action code and an entity type this build does not know,
//     so the neutral fallback is exercised rather than assumed;
//   * two events sharing one timestamp to the microsecond, because `now()` is
//     the transaction timestamp and a tie is reachable rather than theoretical.
// ---------------------------------------------------------------------------

const String createdProductAuditId = 'a1b2c3d4-e5f6-4071-8283-94a5b6c7d8e9';
const String updatedRetailerAuditId = 'b2c3d4e5-f607-4182-8394-a5b6c7d8e9f0';
const String statusChangedAuditId = 'c3d4e5f6-0718-4293-84a5-b6c7d8e9f0a1';
const String shopAddedAuditId = 'd4e5f607-1829-43a4-85b6-c7d8e9f0a1b2';
const String futureActionAuditId = 'e5f60718-293a-44b5-86c7-d8e9f0a1b2c3';

/// The tied pair. Ordered by id **descending**, so `f6…` comes before `00…` —
/// which is the whole point of the fixture: a timestamp-only cursor could not
/// tell them apart.
const String tiedLaterAuditId = 'f6071829-3a4b-45c6-87d8-e9f0a1b2c3d4';
const String tiedEarlierAuditId = '0060718c-3a4b-45c6-87d8-e9f0a1b2c3d4';

/// One shared instant, so the tie-break by id is exercised for real.
final DateTime tiedInstant = DateTime.utc(2026, 7, 26, 1, 25, 0, 0, 123);

/// A named colleague created a product. The ordinary, fully attributed row.
final VendorAuditLogEntry createdProductEvent = VendorAuditLogEntry(
  auditLogId: createdProductAuditId,
  occurredAt: DateTime.utc(2026, 7, 26, 9, 5),
  actionCode: 'PRODUCT_CREATED',
  entityType: 'VENDOR_PRODUCT',
  entityDisplayName: 'Espresso Beans',
  actorType: VendorAuditActorType.user,
  actorDisplayName: 'Ada Vendor',
);

/// An actor id is on the row but resolves to no membership of this Vendor.
final VendorAuditLogEntry unknownActorEvent = VendorAuditLogEntry(
  auditLogId: updatedRetailerAuditId,
  occurredAt: DateTime.utc(2026, 7, 26, 8, 40),
  actionCode: 'RETAILER_ONBOARDED',
  entityType: 'RETAILER_ORGANIZATION',
  entityDisplayName: 'Acme Retail',
  actorType: VendorAuditActorType.unknown,
  actorDisplayName: null,
);

/// No actor identity remains — the one genuinely ambiguous state.
final VendorAuditLogEntry systemActorEvent = VendorAuditLogEntry(
  auditLogId: statusChangedAuditId,
  occurredAt: DateTime.utc(2026, 7, 25, 17, 12),
  actionCode: 'PRODUCT_DEACTIVATED',
  entityType: 'VENDOR_PRODUCT',
  entityDisplayName: 'Espresso Beans',
  actorType: VendorAuditActorType.system,
  actorDisplayName: null,
);

/// A whitelisted entity type whose metadata carried no usable name snapshot.
final VendorAuditLogEntry noEntityNameEvent = VendorAuditLogEntry(
  auditLogId: shopAddedAuditId,
  occurredAt: DateTime.utc(2026, 7, 25, 11, 0),
  actionCode: 'RETAILER_SHOP_ADDED',
  entityType: 'RETAILER_SHOP',
  entityDisplayName: null,
  actorType: VendorAuditActorType.user,
  actorDisplayName: 'Ada Vendor',
);

/// An action code and an entity type a future migration might write. Both must
/// stay visible and neutral rather than being dropped or guessed at.
final VendorAuditLogEntry futureCodeEvent = VendorAuditLogEntry(
  auditLogId: futureActionAuditId,
  occurredAt: DateTime.utc(2026, 7, 24, 6, 30),
  actionCode: 'SOMETHING_NOT_YET_INVENTED',
  entityType: 'FUTURE_ENTITY',
  entityDisplayName: null,
  actorType: VendorAuditActorType.user,
  actorDisplayName: 'Ada Vendor',
);

/// The later half of a tied pair — `occurred_at desc, audit_log_id desc` puts
/// the higher id first.
final VendorAuditLogEntry tiedLaterEvent = VendorAuditLogEntry(
  auditLogId: tiedLaterAuditId,
  occurredAt: tiedInstant,
  actionCode: 'PRODUCT_ASSIGNED_TO_RETAILER',
  entityType: 'VENDOR_PRODUCT',
  entityDisplayName: 'Espresso Beans',
  actorType: VendorAuditActorType.user,
  actorDisplayName: 'Ada Vendor',
);

/// The earlier half of the tied pair, by id.
final VendorAuditLogEntry tiedEarlierEvent = VendorAuditLogEntry(
  auditLogId: tiedEarlierAuditId,
  occurredAt: tiedInstant,
  actionCode: 'PRODUCT_UNASSIGNED_FROM_RETAILER',
  entityType: 'VENDOR_PRODUCT',
  entityDisplayName: 'Espresso Beans',
  actorType: VendorAuditActorType.user,
  actorDisplayName: 'Ada Vendor',
);

/// The newest page, in the backend's order.
final List<VendorAuditLogEntry> auditFirstPage = <VendorAuditLogEntry>[
  createdProductEvent,
  unknownActorEvent,
  systemActorEvent,
  noEntityNameEvent,
  futureCodeEvent,
];

/// A page of older rows, for the load-more path.
final List<VendorAuditLogEntry> auditSecondPage = <VendorAuditLogEntry>[
  tiedLaterEvent,
  tiedEarlierEvent,
];

/// The whole history, both pages, in one ordered list.
final List<VendorAuditLogEntry> auditWholeHistory = <VendorAuditLogEntry>[
  ...auditFirstPage,
  ...auditSecondPage,
];

/// One `list_vendor_audit_logs(...)` row, as PostgREST returns it.
///
/// Seven keys, in the contract's own order, and **no** `metadata`, `entity_id`,
/// `actor_profile_id`, `ip_address` or `user_agent` key — the function returns
/// none of them.
Map<String, Object?> auditLogRow({
  Object? auditLogId = createdProductAuditId,
  Object? occurredAt = '2026-07-26T09:05:00+00:00',
  Object? actionCode = 'PRODUCT_CREATED',
  Object? entityType = 'VENDOR_PRODUCT',
  Object? entityDisplayName = 'Espresso Beans',
  Object? actorType = 'USER',
  Object? actorDisplayName = 'Ada Vendor',
}) => <String, Object?>{
  'audit_log_id': auditLogId,
  'occurred_at': occurredAt,
  'action_code': actionCode,
  'entity_type': entityType,
  'entity_display_name': entityDisplayName,
  'actor_type': actorType,
  'actor_display_name': actorDisplayName,
};

/// A `list_vendor_audit_logs(...)` body of two rows.
List<Map<String, Object?>> auditLogRows() => <Map<String, Object?>>[
  auditLogRow(),
  auditLogRow(
    auditLogId: statusChangedAuditId,
    occurredAt: '2026-07-25T17:12:00+00:00',
    actionCode: 'PRODUCT_DEACTIVATED',
    entityDisplayName: null,
    actorType: 'SYSTEM',
    actorDisplayName: null,
  ),
];

/// A synthetic history of [count] events, newest first.
///
/// Ids are generated so that they sort **descending** in step with the
/// timestamps, exactly as `occurred_at desc, audit_log_id desc` orders real
/// rows — so a page boundary in this fixture falls where the backend would put
/// one. Each event is distinguishable by its entity name, so a test can assert
/// *which* rows arrived rather than only how many.
///
/// Used wherever a test needs more than one page: the client asks for 50 rows
/// and treats anything shorter as the end, so a two-page history is a history of
/// more than 50 events.
List<VendorAuditLogEntry> auditHistoryOf(int count) {
  return List<VendorAuditLogEntry>.generate(
    count,
    (int index) => VendorAuditLogEntry(
      auditLogId: syntheticAuditId(index),
      occurredAt: DateTime.utc(
        2026,
        7,
        26,
        9,
        5,
      ).subtract(Duration(minutes: index)),
      actionCode: 'PRODUCT_UPDATED',
      entityType: 'VENDOR_PRODUCT',
      entityDisplayName: 'Event $index',
      actorType: VendorAuditActorType.user,
      actorDisplayName: 'Ada Vendor',
    ),
    growable: false,
  );
}

/// A well-formed uuid that descends as [index] rises.
String syntheticAuditId(int index) {
  final String head = (99999999 - index).toString().padLeft(8, '0');
  return '$head-0000-4000-8000-000000000000';
}

/// A read that failed the way an unreadable body does.
ReadResult<T> unavailableAuditRead<T>() =>
    ReadFailure<T>(const UnavailableFailure());

/// A read the backend refused with `42501` — which covers a caller who is not
/// signed in, is not a Vendor Super Admin, whose profile or membership is
/// suspended, or whose role no longer holds the audit read permission. All of
/// them are the same answer here, exactly as they are in SQL.
ReadResult<T> deniedAuditRead<T>() => ReadFailure<T>(const DeniedFailure());
