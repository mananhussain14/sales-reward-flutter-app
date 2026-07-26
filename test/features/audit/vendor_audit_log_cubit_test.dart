import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/core/result/read_result.dart';
import 'package:sale_reward/features/audit/data/datasources/vendor_audit_log_rpc_data_source.dart';
import 'package:sale_reward/features/audit/domain/entities/vendor_audit_log_entry.dart';
import 'package:sale_reward/features/audit/presentation/vendor/cubit/vendor_audit_log_cubit.dart';

import '../../support/vendor_audit_log_fakes.dart';

/// The paging, refresh and clearing rules, exercised over a fake that pages a
/// real history.
///
/// The properties under test are the ones a keyset client gets wrong:
///
/// * the cursor is **both halves of the final loaded row**, never an offset,
///   never a timestamp alone, never a remembered position;
/// * a refresh **replaces** and re-anchors rather than appending;
/// * three different failures affect three different things;
/// * a stale answer from a previous session cannot repopulate anything.
void main() {
  late FakeVendorAuditLogRepository repository;

  setUp(() => repository = FakeVendorAuditLogRepository());

  VendorAuditLogCubit build() => VendorAuditLogCubit(repository);

  group('the first page', () {
    test('starts in initial with nothing loaded', () {
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      expect(cubit.state.phase, VendorAuditLogPhase.initial);
      expect(cubit.state.events, isEmpty);
      expect(cubit.state.hasReachedEnd, isFalse);
      expect(cubit.state.isBusy, isFalse);
    });

    test('shows the loading phase while the first read is in flight', () async {
      repository.manual = true;
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      unawaited(cubit.load());
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, VendorAuditLogPhase.loading);
      expect(cubit.state.isRefreshing, isTrue);
      expect(cubit.state.events, isEmpty);

      repository.complete();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, VendorAuditLogPhase.ready);
      expect(cubit.state.isRefreshing, isFalse);
    });

    test('a successful read holds the rows in the backend order', () async {
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.phase, VendorAuditLogPhase.ready);
      expect(
        cubit.state.events.map((VendorAuditLogEntry e) => e.auditLogId),
        auditFirstPage.map((VendorAuditLogEntry e) => e.auditLogId),
      );
      expect(cubit.state.loadedCount, auditFirstPage.length);
    });

    test('it sends no cursor', () async {
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();

      expect(repository.requestedCursors, <VendorAuditLogCursor?>[null]);
    });

    test('an empty first page is a real, non-failed answer', () async {
      repository.history = <VendorAuditLogEntry>[];
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.phase, VendorAuditLogPhase.ready);
      expect(cubit.state.isEmpty, isTrue);
      expect(cubit.state.hasFailedFirstRead, isFalse);
      expect(cubit.state.failure, isNull);
    });

    test('a failed first read keeps the failure and shows no rows', () async {
      repository.result = deniedAuditRead<List<VendorAuditLogEntry>>();
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.hasFailedFirstRead, isTrue);
      expect(cubit.state.failure, isA<DeniedFailure>());
      // Emphatically not an empty history: those are opposite claims.
      expect(cubit.state.isEmpty, isFalse);
    });

    test('a retry after a failure can succeed', () async {
      repository.result = unavailableAuditRead<List<VendorAuditLogEntry>>();
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();
      expect(cubit.state.hasFailedFirstRead, isTrue);

      repository.result = null;
      await cubit.load();

      expect(cubit.state.phase, VendorAuditLogPhase.ready);
      expect(cubit.state.events, hasLength(auditFirstPage.length));
      expect(cubit.state.failure, isNull);
    });

    test('a short first page already means the end of the history', () async {
      // Five rows against a fifty-row request: there is nothing older, and the
      // client knows it without spending a second round trip to find out.
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.hasReachedEnd, isTrue);
      expect(cubit.state.canLoadMore, isFalse);
      expect(cubit.state.showsEndOfHistory, isTrue);
    });

    test('a full first page does not claim the end', () async {
      repository.history = auditHistoryOf(60);
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.events, hasLength(50));
      expect(cubit.state.hasReachedEnd, isFalse);
      expect(cubit.state.canLoadMore, isTrue);
    });
  });

  group('refresh', () {
    test('replaces the loaded rows rather than appending them', () async {
      repository.history = auditHistoryOf(60);
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.loadMore();
      expect(cubit.state.events, hasLength(60));

      await cubit.refresh();

      // The newest page, and nothing spliced beneath it.
      expect(cubit.state.events, hasLength(50));
      expect(cubit.state.events.first.auditLogId, syntheticAuditId(0));
      expect(cubit.state.events.last.auditLogId, syntheticAuditId(49));
    });

    test('sends both cursor halves as null', () async {
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.refresh();

      expect(repository.requestedCursors, <VendorAuditLogCursor?>[null, null]);
      expect(repository.olderCursors, isEmpty);
    });

    test('resets the end-of-list state from the returned page', () async {
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();
      expect(cubit.state.hasReachedEnd, isTrue);

      // The history has grown past one page since the last read.
      repository.history = auditHistoryOf(60);
      await cubit.refresh();

      expect(cubit.state.hasReachedEnd, isFalse);
      expect(cubit.state.canLoadMore, isTrue);
    });

    test('a newer event appears at the head', () async {
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();

      final VendorAuditLogEntry newest = VendorAuditLogEntry(
        auditLogId: tiedLaterAuditId,
        occurredAt: DateTime.utc(2026, 7, 26, 10, 0),
        actionCode: 'PRODUCT_UPDATED',
        entityType: 'VENDOR_PRODUCT',
        entityDisplayName: 'Espresso Beans',
        actorType: createdProductEvent.actorType,
        actorDisplayName: 'Ada Vendor',
      );
      repository.history = <VendorAuditLogEntry>[newest, ...auditFirstPage];
      await cubit.refresh();

      expect(cubit.state.events.first.auditLogId, tiedLaterAuditId);
      expect(cubit.state.events, hasLength(auditFirstPage.length + 1));
    });

    test('a failed refresh preserves the stale rows', () async {
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();
      final List<VendorAuditLogEntry> loaded = cubit.state.events;

      repository.result = unavailableAuditRead<List<VendorAuditLogEntry>>();
      await cubit.refresh();

      expect(cubit.state.events, loaded);
      expect(cubit.state.isStale, isTrue);
      expect(cubit.state.failure, isA<UnavailableFailure>());
      // Not the whole-screen failure state: rows are still on show.
      expect(cubit.state.hasFailedFirstRead, isFalse);
    });

    test('a retry after a failed refresh clears the notice', () async {
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();
      repository.result = unavailableAuditRead<List<VendorAuditLogEntry>>();
      await cubit.refresh();
      expect(cubit.state.isStale, isTrue);

      repository.result = null;
      await cubit.refresh();

      expect(cubit.state.isStale, isFalse);
      expect(cubit.state.failure, isNull);
    });

    test('an empty successful refresh means nothing is recorded now', () async {
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();
      repository.history = <VendorAuditLogEntry>[];
      await cubit.refresh();

      expect(cubit.state.isEmpty, isTrue);
      expect(cubit.state.failure, isNull);
    });

    test('a second refresh while one is in flight is a no-op', () async {
      repository.manual = true;
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      unawaited(cubit.load());
      await Future<void>.delayed(Duration.zero);
      unawaited(cubit.refresh());
      unawaited(cubit.refresh());
      await Future<void>.delayed(Duration.zero);

      expect(repository.callCount, 1);
      expect(repository.pendingCount, 1);
    });
  });

  group('older pages', () {
    test('the cursor is both halves of the final loaded row', () async {
      repository.history = auditHistoryOf(60);
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();
      final VendorAuditLogEntry last = cubit.state.events.last;
      await cubit.loadMore();

      expect(repository.olderCursors, hasLength(1));
      expect(repository.olderCursors.single.auditLogId, last.auditLogId);
      expect(repository.olderCursors.single.occurredAt, last.occurredAt);
      // Never a first-row cursor, never a synthesised one.
      expect(
        repository.olderCursors.single.auditLogId,
        isNot(cubit.state.events.first.auditLogId),
      );
    });

    test('older rows are appended beneath the loaded ones', () async {
      repository.history = auditHistoryOf(60);
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.loadMore();

      expect(cubit.state.events, hasLength(60));
      expect(cubit.state.events.first.auditLogId, syntheticAuditId(0));
      expect(cubit.state.events[50].auditLogId, syntheticAuditId(50));
      expect(cubit.state.events.last.auditLogId, syntheticAuditId(59));
    });

    test('the order stays strictly newest-first across the join', () async {
      repository.history = auditHistoryOf(60);
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.loadMore();

      for (int i = 1; i < cubit.state.events.length; i++) {
        expect(
          cubit.state.events[i].occurredAt.isBefore(
            cubit.state.events[i - 1].occurredAt,
          ),
          isTrue,
          reason: 'row $i is not older than the row above it',
        );
      }
    });

    test('a tied timestamp keeps the backend id order', () async {
      // `now()` is the transaction timestamp, so two events written together tie
      // exactly. The order is the backend's and is never recomputed here.
      repository.history = <VendorAuditLogEntry>[
        tiedLaterEvent,
        tiedEarlierEvent,
      ];
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.events.first.auditLogId, tiedLaterAuditId);
      expect(cubit.state.events.last.auditLogId, tiedEarlierAuditId);
      expect(
        cubit.state.events.first.occurredAt,
        cubit.state.events.last.occurredAt,
      );
      // And the cursor is the *lower* id of the tied pair, so a next page
      // cannot re-emit either of them.
      await cubit.refresh();
      expect(repository.olderCursors, isEmpty);
    });

    test('an empty older page marks the end', () async {
      repository.history = auditHistoryOf(50);
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();
      expect(cubit.state.hasReachedEnd, isFalse);

      await cubit.loadMore();

      expect(cubit.state.hasReachedEnd, isTrue);
      expect(cubit.state.events, hasLength(50));
      expect(cubit.state.showsEndOfHistory, isTrue);
      expect(cubit.state.canLoadMore, isFalse);
    });

    test('a further call after the end issues no request', () async {
      repository.history = auditHistoryOf(50);
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.loadMore();
      final int calls = repository.callCount;

      await cubit.loadMore();

      expect(repository.callCount, calls);
    });

    test('it is a no-op before anything is loaded', () async {
      // There is no final row to take a cursor from, so there is nothing to ask.
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.loadMore();

      expect(repository.callCount, 0);
    });

    test('a failed older page preserves everything already loaded', () async {
      repository.history = auditHistoryOf(60);
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();
      final List<VendorAuditLogEntry> loaded = cubit.state.events;

      repository.result = unavailableAuditRead<List<VendorAuditLogEntry>>();
      await cubit.loadMore();

      expect(cubit.state.events, loaded);
      expect(cubit.state.loadMoreFailure, isA<UnavailableFailure>());
      // A failed read is not evidence that the history ended, and it says
      // nothing about the rows above it.
      expect(cubit.state.hasReachedEnd, isFalse);
      expect(cubit.state.phase, VendorAuditLogPhase.ready);
      expect(cubit.state.failure, isNull);
    });

    test('retrying a failed older page uses the same cursor', () async {
      repository.history = auditHistoryOf(60);
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();
      repository.result = unavailableAuditRead<List<VendorAuditLogEntry>>();
      await cubit.loadMore();

      repository.result = null;
      await cubit.loadMore();

      expect(repository.olderCursors, hasLength(2));
      expect(
        repository.olderCursors.first.auditLogId,
        repository.olderCursors.last.auditLogId,
      );
      expect(cubit.state.events, hasLength(60));
      expect(cubit.state.loadMoreFailure, isNull);
    });

    test('a second call while one is in flight is a no-op', () async {
      repository.history = auditHistoryOf(60);
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();
      repository.manual = true;

      unawaited(cubit.loadMore());
      unawaited(cubit.loadMore());
      unawaited(cubit.loadMore());
      await Future<void>.delayed(Duration.zero);

      expect(repository.pendingCount, 1);
      expect(repository.olderCursors, hasLength(1));
    });

    test(
      'a refresh mid-flight is refused, so the cursor is not lost',
      () async {
        repository.history = auditHistoryOf(60);
        final VendorAuditLogCubit cubit = build();
        addTearDown(cubit.close);

        await cubit.load();
        repository.manual = true;
        unawaited(cubit.loadMore());
        await Future<void>.delayed(Duration.zero);

        await cubit.refresh();

        expect(repository.pendingCount, 1);
        expect(repository.callCount, 2);
      },
    );

    test('a refresh resets pagination back to the first page', () async {
      repository.history = auditHistoryOf(60);
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.loadMore();
      expect(cubit.state.hasReachedEnd, isTrue);

      await cubit.refresh();
      expect(cubit.state.events, hasLength(50));
      expect(cubit.state.hasReachedEnd, isFalse);

      // And the next older page is anchored to the REFRESHED list's final row,
      // not to the position the previous traversal had reached.
      await cubit.loadMore();
      expect(repository.olderCursors.last.auditLogId, syntheticAuditId(49));
    });

    test('a refresh clears a pending older-page failure', () async {
      repository.history = auditHistoryOf(60);
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();
      repository.result = unavailableAuditRead<List<VendorAuditLogEntry>>();
      await cubit.loadMore();
      expect(cubit.state.loadMoreFailure, isNotNull);

      repository.result = null;
      await cubit.refresh();

      expect(cubit.state.loadMoreFailure, isNull);
    });
  });

  group('defensive de-duplication', () {
    test('a repeated id in an older page is dropped, order intact', () async {
      // The backend's strict `<` against a unique composite key cannot produce
      // this. Appending a duplicate would break the list keys and, because the
      // cursor comes from the final row, could stall paging on a repeating page.
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      repository.history = auditHistoryOf(60);
      await cubit.load();

      repository.result = ReadSuccess<List<VendorAuditLogEntry>>(
        <VendorAuditLogEntry>[
          // Two rows already held, then one genuinely older.
          cubit.state.events.first,
          cubit.state.events.last,
          auditHistoryOf(60)[50],
        ],
      );
      await cubit.loadMore();

      expect(cubit.state.events, hasLength(51));
      expect(cubit.state.events.last.auditLogId, syntheticAuditId(50));
      expect(
        cubit.state.events
            .map((VendorAuditLogEntry e) => e.auditLogId)
            .toSet()
            .length,
        cubit.state.events.length,
      );
    });

    test('a repeated id within one page is dropped too', () async {
      repository.result = ReadSuccess<List<VendorAuditLogEntry>>(
        <VendorAuditLogEntry>[
          createdProductEvent,
          createdProductEvent,
          systemActorEvent,
        ],
      );
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.events, hasLength(2));
      expect(cubit.state.events.first.auditLogId, createdProductAuditId);
      expect(cubit.state.events.last.auditLogId, statusChangedAuditId);
    });

    test('a refresh that returns the same rows does not double them', () async {
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.refresh();
      await cubit.refresh();

      expect(cubit.state.events, hasLength(auditFirstPage.length));
    });
  });

  group('stale answers', () {
    test('a first page landing after a clear is ignored', () async {
      repository.manual = true;
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      unawaited(cubit.load());
      await Future<void>.delayed(Duration.zero);

      cubit.clear();
      repository.complete(
        ReadSuccess<List<VendorAuditLogEntry>>(auditFirstPage),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.events, isEmpty);
      expect(cubit.state.phase, VendorAuditLogPhase.initial);
    });

    test('a refresh landing after a clear is ignored', () async {
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();
      repository.manual = true;
      unawaited(cubit.refresh());
      await Future<void>.delayed(Duration.zero);

      cubit.clear();
      repository.complete(
        ReadSuccess<List<VendorAuditLogEntry>>(auditFirstPage),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.events, isEmpty);
    });

    test('an older page landing after a clear is ignored', () async {
      repository.history = auditHistoryOf(60);
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();
      repository.manual = true;
      unawaited(cubit.loadMore());
      await Future<void>.delayed(Duration.zero);

      cubit.clear();
      repository.complete();
      await Future<void>.delayed(Duration.zero);

      // Appending it would splice one Vendor's history onto another's.
      expect(cubit.state.events, isEmpty);
      expect(cubit.state.hasReachedEnd, isFalse);
    });

    test('a stale read cannot overwrite a newer one', () async {
      repository.manual = true;
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      unawaited(cubit.load());
      await Future<void>.delayed(Duration.zero);
      cubit.clear();
      unawaited(cubit.load());
      await Future<void>.delayed(Duration.zero);
      expect(repository.pendingCount, 2);

      // The newer read answers first, then the stale one.
      repository.completeAt(
        1,
        ReadSuccess<List<VendorAuditLogEntry>>(<VendorAuditLogEntry>[
          systemActorEvent,
        ]),
      );
      await Future<void>.delayed(Duration.zero);
      repository.completeAt(
        0,
        ReadSuccess<List<VendorAuditLogEntry>>(auditFirstPage),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.events, hasLength(1));
      expect(cubit.state.events.single.auditLogId, statusChangedAuditId);
    });
  });

  group('clearing', () {
    test(
      'drops the rows, the cursor, the end flag and both failures',
      () async {
        repository.history = auditHistoryOf(60);
        final VendorAuditLogCubit cubit = build();
        addTearDown(cubit.close);

        await cubit.load();
        await cubit.loadMore();
        expect(cubit.state.events, hasLength(60));
        expect(cubit.state.hasReachedEnd, isTrue);

        cubit.clear();

        expect(cubit.state, const VendorAuditLogState());
        expect(cubit.state.events, isEmpty);
        expect(cubit.state.hasReachedEnd, isFalse);
        expect(cubit.state.failure, isNull);
        expect(cubit.state.loadMoreFailure, isNull);
        expect(cubit.state.isRefreshing, isFalse);
        expect(cubit.state.isLoadingMore, isFalse);
        expect(cubit.state.phase, VendorAuditLogPhase.initial);
      },
    );

    test('a load after a clear starts from the newest page', () async {
      repository.history = auditHistoryOf(60);
      final VendorAuditLogCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.loadMore();
      cubit.clear();
      await cubit.load();

      expect(cubit.state.events, hasLength(50));
      expect(repository.requestedCursors.last, isNull);
    });
  });

  group('the page size the state reports', () {
    test('is the fixed contract value', () {
      expect(vendorAuditLogPageSize, 50);
    });
  });
}
