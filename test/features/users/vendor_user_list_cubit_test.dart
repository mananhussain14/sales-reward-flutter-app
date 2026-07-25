import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/core/result/read_result.dart';
import 'package:sale_reward/features/users/domain/entities/vendor_user_status.dart';
import 'package:sale_reward/features/users/domain/entities/vendor_user_summary.dart';
import 'package:sale_reward/features/users/presentation/vendor/cubit/vendor_user_list_cubit.dart';

import '../../support/vendor_user_fakes.dart';

void main() {
  late FakeVendorUserRepository repository;
  late VendorUserListCubit cubit;

  setUp(() {
    repository = FakeVendorUserRepository();
    cubit = VendorUserListCubit(repository);
  });

  tearDown(() => cubit.close());

  /// A third row, so status filtering has something to separate.
  VendorUserSummary suspendedUser() => VendorUserSummary(
    membershipId: foreignMembershipUuid,
    displayName: 'Sam Okonkwo',
    profileStatus: VendorUserStatus.active,
    membershipStatus: VendorUserStatus.suspended,
    membershipCreatedAt: joCreatedAt,
    joinedAt: aminaJoinedAt,
    roleNames: const <String>['Claim Reviewer'],
  );

  group('the first read', () {
    test('starts empty and initial', () {
      expect(cubit.state.phase, VendorUserListPhase.initial);
      expect(cubit.state.users, isEmpty);
      expect(cubit.state.isRefreshing, isFalse);
      expect(cubit.state.failure, isNull);
    });

    test('shows loading, then the directory', () async {
      final List<VendorUserListPhase> phases = <VendorUserListPhase>[];
      cubit.stream.listen((VendorUserListState s) => phases.add(s.phase));

      await cubit.load();
      // The stream is asynchronous; let the last emit reach the listener.
      await Future<void>.delayed(Duration.zero);

      expect(phases, <VendorUserListPhase>[
        VendorUserListPhase.loading,
        VendorUserListPhase.ready,
      ]);
      expect(cubit.state.users, hasLength(2));
      expect(cubit.state.isRefreshing, isFalse);
      expect(repository.usersCallCount, 1);
    });

    test('issues exactly one RPC and opens no detail', () async {
      await cubit.load();

      expect(repository.usersCallCount, 1);
      expect(repository.detailCallCount, 0);
    });

    test('a one-user directory loads', () async {
      repository.usersResult = ReadSuccess<List<VendorUserSummary>>(
        <VendorUserSummary>[aminaSummary],
      );

      await cubit.load();

      expect(cubit.state.users, hasLength(1));
      expect(cubit.state.isOnlyMe, isTrue);
      expect(cubit.state.isEmpty, isFalse);
    });

    test('an empty directory is ready-and-empty, not a failure', () async {
      repository.usersResult = const ReadSuccess<List<VendorUserSummary>>(
        <VendorUserSummary>[],
      );

      await cubit.load();

      expect(cubit.state.phase, VendorUserListPhase.ready);
      expect(cubit.state.isEmpty, isTrue);
      expect(cubit.state.isOnlyMe, isFalse);
      expect(cubit.state.failure, isNull);
    });

    test('a denial is a failure and keeps the list empty', () async {
      repository.usersResult = deniedUserRead<List<VendorUserSummary>>();

      await cubit.load();

      expect(cubit.state.phase, VendorUserListPhase.failed);
      expect(cubit.state.failure, isA<DeniedFailure>());
      expect(cubit.state.users, isEmpty);
      // A denial is not "this Vendor has no users".
      expect(cubit.state.isEmpty, isFalse);
    });

    test('an outage is a failure that a retry can clear', () async {
      repository.usersResult = unavailableUserRead<List<VendorUserSummary>>();
      await cubit.load();
      expect(cubit.state.phase, VendorUserListPhase.failed);

      repository.usersResult = ReadSuccess<List<VendorUserSummary>>(
        <VendorUserSummary>[aminaSummary],
      );
      await cubit.load();

      expect(cubit.state.phase, VendorUserListPhase.ready);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.users, hasLength(1));
      expect(repository.usersCallCount, 2);
    });
  });

  group('refresh', () {
    test('keeps the loaded rows on screen while it runs', () async {
      await cubit.load();

      final Future<void> refreshing = cubit.refresh();
      expect(cubit.state.phase, VendorUserListPhase.ready);
      expect(cubit.state.isRefreshing, isTrue);
      expect(cubit.state.users, hasLength(2));

      await refreshing;
      expect(cubit.state.isRefreshing, isFalse);
    });

    test('a failed refresh keeps the previous rows', () async {
      await cubit.load();
      repository.usersResult = unavailableUserRead<List<VendorUserSummary>>();

      await cubit.refresh();

      expect(cubit.state.phase, VendorUserListPhase.failed);
      expect(cubit.state.failure, isA<UnavailableFailure>());
      // Still the last thing the backend actually said.
      expect(cubit.state.users, hasLength(2));
    });

    test('a refresh over an empty list shows loading again', () async {
      repository.usersResult = const ReadSuccess<List<VendorUserSummary>>(
        <VendorUserSummary>[],
      );
      await cubit.load();

      final List<VendorUserListPhase> phases = <VendorUserListPhase>[];
      cubit.stream.listen((VendorUserListState s) => phases.add(s.phase));
      await cubit.refresh();
      await Future<void>.delayed(Duration.zero);

      expect(phases.first, VendorUserListPhase.loading);
    });

    test('a second refresh while one is in flight is dropped', () async {
      await cubit.load();
      repository.manualUsers = true;

      final Future<void> first = cubit.refresh();
      final Future<void> second = cubit.refresh();
      final Future<void> third = cubit.refresh();

      // One in-flight request, not three.
      expect(repository.pendingUserCount, 1);
      expect(repository.usersCallCount, 2); // the load, plus one refresh

      repository.completeUsers();
      await Future.wait(<Future<void>>[first, second, third]);

      expect(cubit.state.isRefreshing, isFalse);
      expect(repository.usersCallCount, 2);
    });

    test('load is also blocked while a refresh is in flight', () async {
      await cubit.load();
      repository.manualUsers = true;

      final Future<void> refreshing = cubit.refresh();
      await cubit.load();

      expect(repository.usersCallCount, 2);

      repository.completeUsers();
      await refreshing;
    });
  });

  group('local display-name search', () {
    setUp(() async {
      await cubit.load();
    });

    test('matches a display name case-insensitively', () {
      cubit.search('AMINA');

      expect(
        cubit.state.visibleUsers.map((VendorUserSummary u) => u.displayName),
        <String>['Amina Rahman'],
      );
      expect(cubit.state.totalCount, 2);
    });

    test('matches a fragment anywhere in the name', () {
      cubit.search('kamu');
      expect(cubit.state.visibleUsers.single.displayName, 'Jo Nakamura');
    });

    test('a term matching nothing is "no matches", not "no users"', () {
      cubit.search('zzz');

      expect(cubit.state.visibleUsers, isEmpty);
      expect(cubit.state.hasNoMatches, isTrue);
      expect(cubit.state.isEmpty, isFalse);
    });

    test('whitespace alone does not narrow anything', () {
      cubit.search('   ');

      expect(cubit.state.hasFilters, isFalse);
      expect(cubit.state.visibleUsers, hasLength(2));
    });

    test('an unnarrowed list is the backend list, in order', () {
      expect(cubit.state.visibleUsers, same(cubit.state.users));
      expect(
        cubit.state.visibleUsers.map((VendorUserSummary u) => u.displayName),
        <String>['Amina Rahman', 'Jo Nakamura'],
      );
    });

    test('narrowing preserves the backend order', () {
      cubit.search('a');
      expect(
        cubit.state.visibleUsers.map((VendorUserSummary u) => u.displayName),
        <String>['Amina Rahman', 'Jo Nakamura'],
      );
    });

    test('clearing the term restores the original ordering', () {
      cubit.search('jo');
      cubit.search('');

      expect(cubit.state.hasFilters, isFalse);
      expect(cubit.state.visibleUsers, same(cubit.state.users));
    });

    test('the search is never sent to the backend', () {
      final int before = repository.usersCallCount;
      cubit.search('amina');
      expect(repository.usersCallCount, before);
    });
  });

  group('local status filtering', () {
    setUp(() async {
      repository.usersResult = ReadSuccess<List<VendorUserSummary>>(
        <VendorUserSummary>[aminaSummary, joSummary, suspendedUser()],
      );
      await cubit.load();
    });

    test('offers only the statuses actually present in the data', () {
      expect(cubit.state.presentProfileStatuses, <VendorUserStatus>[
        VendorUserStatus.invited,
        VendorUserStatus.active,
      ]);
      expect(cubit.state.presentMembershipStatuses, <VendorUserStatus>[
        VendorUserStatus.invited,
        VendorUserStatus.active,
        VendorUserStatus.suspended,
      ]);
    });

    test('filters on profile status', () {
      cubit.filterByProfileStatus(VendorUserStatus.invited);

      expect(cubit.state.visibleUsers.single.displayName, 'Jo Nakamura');
    });

    test('filters on membership status', () {
      cubit.filterByMembershipStatus(VendorUserStatus.suspended);

      expect(cubit.state.visibleUsers.single.displayName, 'Sam Okonkwo');
    });

    test('the two filters are independent and compose', () {
      // The case one combined filter would have made unreachable: an active
      // profile holding a suspended membership.
      cubit.filterByProfileStatus(VendorUserStatus.active);
      cubit.filterByMembershipStatus(VendorUserStatus.suspended);

      expect(cubit.state.visibleUsers.single.displayName, 'Sam Okonkwo');
    });

    test('search and both filters compose', () {
      cubit.search('sam');
      cubit.filterByProfileStatus(VendorUserStatus.active);
      cubit.filterByMembershipStatus(VendorUserStatus.suspended);

      expect(cubit.state.visibleUsers, hasLength(1));

      cubit.search('amina');
      expect(cubit.state.visibleUsers, isEmpty);
    });

    test('null clears each filter individually', () {
      cubit.filterByProfileStatus(VendorUserStatus.invited);
      cubit.filterByMembershipStatus(VendorUserStatus.invited);

      cubit.filterByProfileStatus(null);
      expect(cubit.state.profileFilter, isNull);
      expect(cubit.state.membershipFilter, VendorUserStatus.invited);

      cubit.filterByMembershipStatus(null);
      expect(cubit.state.membershipFilter, isNull);
      expect(cubit.state.visibleUsers, hasLength(3));
    });

    test('clearFilters drops the term and both filters', () {
      cubit.search('amina');
      cubit.filterByProfileStatus(VendorUserStatus.active);
      cubit.filterByMembershipStatus(VendorUserStatus.active);

      cubit.clearFilters();

      expect(cubit.state.searchTerm, isEmpty);
      expect(cubit.state.profileFilter, isNull);
      expect(cubit.state.membershipFilter, isNull);
      expect(cubit.state.hasFilters, isFalse);
      expect(cubit.state.visibleUsers, same(cubit.state.users));
    });

    test(
      'an unknown status is still offered when one actually arrived',
      () async {
        // Hiding those rows behind no chip at all would make them unreachable.
        repository.usersResult =
            ReadSuccess<List<VendorUserSummary>>(<VendorUserSummary>[
              VendorUserSummary(
                membershipId: foreignMembershipUuid,
                displayName: 'Future Person',
                profileStatus: VendorUserStatus.unknown,
                membershipStatus: VendorUserStatus.unknown,
                membershipCreatedAt: joCreatedAt,
                joinedAt: null,
                roleNames: const <String>[],
              ),
            ]);
        await cubit.load();

        expect(cubit.state.presentMembershipStatuses, <VendorUserStatus>[
          VendorUserStatus.unknown,
        ]);
      },
    );
  });

  group('derived counts', () {
    test('are counted from the returned membership statuses', () async {
      repository.usersResult = ReadSuccess<List<VendorUserSummary>>(
        <VendorUserSummary>[aminaSummary, joSummary, suspendedUser()],
      );
      await cubit.load();

      expect(cubit.state.totalCount, 3);
      expect(cubit.state.activeCount, 1);
      expect(cubit.state.invitedCount, 1);
      expect(cubit.state.inactiveCount, 1);
    });

    test('an unknown status is counted in no bucket, only the total', () async {
      // The breakdown never claims to be exhaustive; the total is always the
      // honest number.
      repository.usersResult =
          ReadSuccess<List<VendorUserSummary>>(<VendorUserSummary>[
            VendorUserSummary(
              membershipId: foreignMembershipUuid,
              displayName: 'Future Person',
              profileStatus: VendorUserStatus.unknown,
              membershipStatus: VendorUserStatus.unknown,
              membershipCreatedAt: joCreatedAt,
              joinedAt: null,
              roleNames: const <String>[],
            ),
          ]);
      await cubit.load();

      expect(cubit.state.totalCount, 1);
      expect(cubit.state.activeCount, 0);
      expect(cubit.state.invitedCount, 0);
      expect(cubit.state.inactiveCount, 0);
    });

    test('counts follow the whole list, not the narrowed view', () async {
      await cubit.load();
      cubit.search('amina');

      expect(cubit.state.visibleUsers, hasLength(1));
      expect(cubit.state.totalCount, 2);
    });
  });

  group('private data is cleared on a session change', () {
    test('clear drops rows, search, both filters and any failure', () async {
      await cubit.load();
      cubit.search('amina');
      cubit.filterByProfileStatus(VendorUserStatus.active);
      cubit.filterByMembershipStatus(VendorUserStatus.active);

      cubit.clear();

      expect(cubit.state.users, isEmpty);
      // A search term is a fragment of a colleague's name — private too.
      expect(cubit.state.searchTerm, isEmpty);
      expect(cubit.state.profileFilter, isNull);
      expect(cubit.state.membershipFilter, isNull);
      expect(cubit.state.phase, VendorUserListPhase.initial);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.isRefreshing, isFalse);
      expect(cubit.state.totalCount, 0);
    });

    test('an in-flight read cannot refill a cleared directory', () async {
      repository.manualUsers = true;
      final Future<void> pending = cubit.load();

      cubit.clear();
      repository.completeUsers();
      await pending;

      expect(cubit.state.users, isEmpty);
      expect(cubit.state.phase, VendorUserListPhase.initial);
    });

    test('a read that lands after close is dropped', () async {
      repository.manualUsers = true;
      final Future<void> pending = cubit.load();

      await cubit.close();
      repository.completeUsers();
      await pending;

      expect(repository.usersCallCount, 1);
    });

    test('loading again after a clear works', () async {
      await cubit.load();
      cubit.clear();

      await cubit.load();

      expect(cubit.state.users, hasLength(2));
      expect(repository.usersCallCount, 2);
    });
  });
}
