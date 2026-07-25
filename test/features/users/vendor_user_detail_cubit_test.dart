import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/core/result/read_result.dart';
import 'package:sale_reward/features/users/domain/entities/vendor_user_detail.dart';
import 'package:sale_reward/features/users/presentation/vendor/cubit/vendor_user_detail_cubit.dart';

import '../../support/vendor_user_fakes.dart';

void main() {
  late FakeVendorUserRepository repository;
  late VendorUserDetailCubit cubit;

  setUp(() {
    repository = FakeVendorUserRepository();
    cubit = VendorUserDetailCubit(repository);
  });

  tearDown(() => cubit.close());

  group('loading one user', () {
    test('starts initial and holds nothing', () {
      expect(cubit.state.phase, VendorUserDetailPhase.initial);
      expect(cubit.state.membershipId, isNull);
      expect(cubit.state.detail, isNull);
      expect(cubit.state.failure, isNull);
    });

    test('shows loading, then the detail — one call', () async {
      final List<VendorUserDetailPhase> phases = <VendorUserDetailPhase>[];
      cubit.stream.listen((VendorUserDetailState s) => phases.add(s.phase));

      await cubit.open(aminaMembershipUuid);
      await Future<void>.delayed(Duration.zero);

      expect(phases, <VendorUserDetailPhase>[
        VendorUserDetailPhase.loading,
        VendorUserDetailPhase.ready,
      ]);
      expect(repository.requestedMembershipIds, <String>[aminaMembershipUuid]);
      expect(cubit.state.detail!.displayName, 'Amina Rahman');
    });

    test('there is no companion read to sequence', () async {
      // Roles arrive inside the same row as a text[]; nothing else is fetched.
      await cubit.open(aminaMembershipUuid);

      expect(repository.detailCallCount, 1);
      expect(repository.usersCallCount, 0);
      expect(cubit.state.detail!.roleNames, hasLength(2));
    });

    test('roles keep the backend order', () async {
      await cubit.open(aminaMembershipUuid);

      expect(cubit.state.detail!.roleNames, <String>[
        'Finance Admin',
        'Vendor Super Admin',
      ]);
    });

    test('an empty role list is loaded as empty', () async {
      await cubit.open(joMembershipUuid);

      expect(cubit.state.detail!.roleNames, isEmpty);
      expect(cubit.state.detail!.hasNoRoles, isTrue);
    });

    test('a null joined date is preserved', () async {
      await cubit.open(joMembershipUuid);

      expect(cubit.state.detail!.joinedAt, isNull);
      // And never substituted with the creation date.
      expect(cubit.state.detail!.membershipCreatedAt, isNotNull);
    });

    test('a null deactivated date is preserved', () async {
      await cubit.open(aminaMembershipUuid);

      expect(cubit.state.detail!.deactivatedAt, isNull);
    });

    test('a set deactivated date is loaded', () async {
      repository.detailResult = ReadSuccess<VendorUserDetail?>(
        deactivatedDetail,
      );

      await cubit.open(joMembershipUuid);

      expect(cubit.state.detail!.deactivatedAt, joDeactivatedAt);
    });
  });

  group('an inaccessible membership', () {
    setUp(() {
      repository.detailResult = const ReadSuccess<VendorUserDetail?>(null);
    });

    test('zero rows becomes notFound', () async {
      await cubit.open(foreignMembershipUuid);

      expect(cubit.state.phase, VendorUserDetailPhase.notFound);
      expect(cubit.state.detail, isNull);
    });

    test('notFound is not a failure and carries no discriminant', () async {
      await cubit.open(foreignMembershipUuid);

      expect(cubit.state.failure, isNull);
    });

    test('an unknown id and a foreign id reach the identical state', () async {
      await cubit.open(foreignMembershipUuid);
      final VendorUserDetailState foreign = cubit.state;

      cubit.clear();
      await cubit.open(aminaMembershipUuid);

      expect(cubit.state.phase, foreign.phase);
      expect(cubit.state.failure, foreign.failure);
      expect(cubit.state.detail, foreign.detail);
    });

    test('a Retailer-owned membership is the same state again', () async {
      // Those rows exist, but not in this organization — so the backend answers
      // zero rows exactly as it does for an id that names nothing.
      await cubit.open(joMembershipUuid);

      expect(cubit.state.phase, VendorUserDetailPhase.notFound);
      expect(cubit.state.failure, isNull);
    });

    test('a malformed id reaches the same state, with no RPC at all', () async {
      final FakeVendorUserRepository real = FakeVendorUserRepository();
      final VendorUserDetailCubit fresh = VendorUserDetailCubit(real);
      addTearDown(fresh.close);
      real.detailResult = const ReadSuccess<VendorUserDetail?>(null);

      await fresh.open('not-a-uuid');

      expect(fresh.state.phase, VendorUserDetailPhase.notFound);
      expect(fresh.state.failure, isNull);
    });

    test('retry re-reads, and finds the same answer', () async {
      await cubit.open(foreignMembershipUuid);

      await cubit.retry();

      expect(cubit.state.phase, VendorUserDetailPhase.notFound);
      expect(repository.detailCallCount, 2);
    });
  });

  group('failures stay failures', () {
    test('an outage is a retryable failure, never a notFound', () async {
      repository.detailResult = unavailableUserRead<VendorUserDetail?>();

      await cubit.open(aminaMembershipUuid);

      expect(cubit.state.phase, VendorUserDetailPhase.failed);
      expect(cubit.state.failure, isA<UnavailableFailure>());
      expect(cubit.state.detail, isNull);
    });

    test('a denial is a denial, never a "not found"', () async {
      repository.detailResult = deniedUserRead<VendorUserDetail?>();

      await cubit.open(aminaMembershipUuid);

      expect(cubit.state.phase, VendorUserDetailPhase.failed);
      expect(cubit.state.failure, isA<DeniedFailure>());
    });

    test('retry after an outage loads the user', () async {
      repository.detailResult = unavailableUserRead<VendorUserDetail?>();
      await cubit.open(aminaMembershipUuid);

      repository.detailResult = null; // back to the id-sensitive default
      await cubit.retry();

      expect(cubit.state.phase, VendorUserDetailPhase.ready);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.detail!.displayName, 'Amina Rahman');
      expect(repository.detailCallCount, 2);
    });

    test('retry does nothing when nothing is open', () async {
      await cubit.retry();

      expect(repository.detailCallCount, 0);
      expect(cubit.state.phase, VendorUserDetailPhase.initial);
    });
  });

  group('duplicate loads are impossible', () {
    test('re-opening the same membership issues nothing', () async {
      await cubit.open(aminaMembershipUuid);

      await cubit.open(aminaMembershipUuid);
      await cubit.open(aminaMembershipUuid);

      expect(repository.detailCallCount, 1);
    });

    test('re-opening while the first read is in flight is a no-op', () async {
      repository.manualDetail = true;

      final Future<void> first = cubit.open(aminaMembershipUuid);
      final Future<void> second = cubit.open(aminaMembershipUuid);

      expect(repository.detailCallCount, 1);

      repository.completeDetail();
      await Future.wait(<Future<void>>[first, second]);

      expect(repository.detailCallCount, 1);
    });

    test('a different membership always starts a fresh read', () async {
      await cubit.open(aminaMembershipUuid);

      await cubit.open(joMembershipUuid);

      expect(repository.requestedMembershipIds, <String>[
        aminaMembershipUuid,
        joMembershipUuid,
      ]);
      expect(cubit.state.detail!.displayName, 'Jo Nakamura');
    });

    test('retry is dropped while a read is in flight', () async {
      repository.manualDetail = true;
      final Future<void> opening = cubit.open(aminaMembershipUuid);

      await cubit.retry();
      expect(repository.detailCallCount, 1);

      repository.completeDetail();
      await opening;
    });

    test('a stale answer cannot overwrite a newer one', () async {
      // The classic race: open A, open B, then let A's response land last.
      repository.manualDetail = true;

      final Future<void> first = cubit.open(aminaMembershipUuid);
      cubit.clear();
      final Future<void> second = cubit.open(joMembershipUuid);

      expect(repository.pendingDetailCount, 2);

      // B answers, then the stale A answers.
      repository.completeDetail(ReadSuccess<VendorUserDetail?>(aminaDetail));
      await first;
      repository.completeDetail(ReadSuccess<VendorUserDetail?>(joDetail));
      await second;

      // The state belongs to the membership that was opened last.
      expect(cubit.state.membershipId, joMembershipUuid);
      expect(cubit.state.detail!.displayName, 'Jo Nakamura');
    });
  });

  group('private data is cleared on a session change', () {
    test('clear empties the detail and the open id', () async {
      await cubit.open(aminaMembershipUuid);

      cubit.clear();

      expect(cubit.state.membershipId, isNull);
      expect(cubit.state.detail, isNull);
      expect(cubit.state.phase, VendorUserDetailPhase.initial);
      expect(cubit.state.failure, isNull);
    });

    test('an in-flight read cannot repopulate a cleared state', () async {
      repository.manualDetail = true;
      final Future<void> pending = cubit.open(aminaMembershipUuid);

      cubit.clear();
      repository.completeDetail();
      await pending;

      expect(cubit.state.detail, isNull);
      expect(cubit.state.phase, VendorUserDetailPhase.initial);
    });

    test('the same membership reloads after a clear', () async {
      await cubit.open(aminaMembershipUuid);
      cubit.clear();

      await cubit.open(aminaMembershipUuid);

      expect(repository.detailCallCount, 2);
      expect(cubit.state.phase, VendorUserDetailPhase.ready);
    });

    test('a read that lands after close is dropped', () async {
      repository.manualDetail = true;
      final Future<void> pending = cubit.open(aminaMembershipUuid);

      await cubit.close();
      repository.completeDetail();
      await pending;

      expect(repository.detailCallCount, 1);
    });
  });
}
