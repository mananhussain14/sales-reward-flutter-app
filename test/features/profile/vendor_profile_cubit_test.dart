import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/core/result/read_result.dart';
import 'package:sale_reward/features/profile/domain/entities/vendor_administrator_profile.dart';
import 'package:sale_reward/features/profile/presentation/vendor/cubit/vendor_profile_cubit.dart';

import '../../support/vendor_profile_fakes.dart';

/// The cubit's job is to hold **one identity** and to be honest about how old it
/// is.
///
/// Three rules it must never break, each tested from several directions:
///
/// 1. **The name and the roles are replaced together or not at all.** They come
///    from one statement about one person, so a merged state could pair one
///    administrator's name with another's entitlements.
/// 2. **A failure never becomes an identity.** Not a blank name, not an empty
///    role list, not a carried-over field.
/// 3. **An answer for a previous identity never lands.** The request token drops
///    a stale first read and a stale refresh alike.
void main() {
  late FakeVendorProfileRepository repository;

  setUp(() => repository = FakeVendorProfileRepository());

  VendorProfileCubit buildCubit() => VendorProfileCubit(repository);

  group('the first read', () {
    test('starts in initial with nothing loaded', () {
      final VendorProfileCubit cubit = buildCubit();

      expect(cubit.state.phase, VendorProfilePhase.initial);
      expect(cubit.state.profile, isNull);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.isRefreshing, isFalse);
      expect(cubit.state.isFirstLoad, isTrue);
      addTearDown(cubit.close);
    });

    test('shows the loading phase while the read is in flight', () async {
      repository.manual = true;
      final VendorProfileCubit cubit = buildCubit();
      addTearDown(cubit.close);

      unawaited(cubit.load());
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, VendorProfilePhase.loading);
      expect(cubit.state.isRefreshing, isTrue);
      expect(cubit.state.isFirstLoad, isTrue);
      // Nothing is shown, and no name is invented, while the answer is unknown.
      expect(cubit.state.profile, isNull);

      repository.complete();
      await Future<void>.delayed(Duration.zero);
    });

    test('a successful read holds the whole profile', () async {
      final VendorProfileCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.phase, VendorProfilePhase.ready);
      expect(cubit.state.profile, aminaAdministratorProfile);
      expect(cubit.state.isRefreshing, isFalse);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.isFirstLoad, isFalse);
    });

    test('several roles are held in the order they arrived', () async {
      repository.nextProfile = reversedOrderProfile;
      final VendorProfileCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.profile!.roleNames, <String>[
        'Vendor Super Admin',
        'Finance Admin',
        'Catalogue Manager',
      ]);
    });

    test('a defensively empty role list is a real answer', () async {
      repository.nextProfile = noRoleAdministratorProfile;
      final VendorProfileCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.phase, VendorProfilePhase.ready);
      expect(cubit.state.profile!.roleNames, isEmpty);
      // Still a real name beside it, and no failure.
      expect(cubit.state.profile!.displayName, 'Amina Rahman');
      expect(cubit.state.hasFailedFirstRead, isFalse);
    });

    test(
      'a failed first read keeps the failure and shows no profile',
      () async {
        repository.result =
            unavailableProfileRead<VendorAdministratorProfile>();
        final VendorProfileCubit cubit = buildCubit();
        addTearDown(cubit.close);

        await cubit.load();

        expect(cubit.state.phase, VendorProfilePhase.failed);
        expect(cubit.state.failure, isA<UnavailableFailure>());
        expect(cubit.state.profile, isNull);
        expect(cubit.state.hasFailedFirstRead, isTrue);
        expect(cubit.state.isStale, isFalse);
      },
    );

    test('a denial is a failure, never a blank profile', () async {
      repository.result = deniedProfileRead<VendorAdministratorProfile>();
      final VendorProfileCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.failure, isA<DeniedFailure>());
      expect(cubit.state.profile, isNull);
    });

    test('a retry after a failure can succeed', () async {
      repository.result = unavailableProfileRead<VendorAdministratorProfile>();
      final VendorProfileCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();
      expect(cubit.state.hasFailedFirstRead, isTrue);

      repository.result = null;
      await cubit.load();

      expect(cubit.state.phase, VendorProfilePhase.ready);
      expect(cubit.state.profile, aminaAdministratorProfile);
      expect(cubit.state.failure, isNull);
      expect(repository.callCount, 2);
    });
  });

  group('refresh', () {
    test('replaces the name and the roles atomically', () async {
      final VendorProfileCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();
      expect(cubit.state.profile, aminaAdministratorProfile);

      // Both fields move. Neither may be carried over.
      repository.nextProfile = joAdministratorProfile;
      await cubit.refresh();

      expect(cubit.state.profile, joAdministratorProfile);
      expect(cubit.state.profile!.displayName, 'Jo Nakamura');
      expect(cubit.state.profile!.roleNames, <String>[
        'Finance Admin',
        'Vendor Super Admin',
      ]);
    });

    test('a role withdrawn between reads disappears, not lingers', () async {
      final VendorProfileCubit cubit = buildCubit();
      addTearDown(cubit.close);

      repository.nextProfile = multiRoleAdministratorProfile;
      await cubit.load();
      expect(cubit.state.profile!.roleNames, hasLength(3));

      repository.nextProfile = aminaAdministratorProfile;
      await cubit.refresh();

      expect(cubit.state.profile!.roleNames, <String>['Vendor Super Admin']);
    });

    test('keeps the profile on screen while it runs', () async {
      final VendorProfileCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();

      repository.manual = true;
      unawaited(cubit.refresh());
      await Future<void>.delayed(Duration.zero);

      // Visibly refreshing, but the previous profile is still on screen — a
      // refresh updates an identity, it does not blank it.
      expect(cubit.state.isRefreshing, isTrue);
      expect(cubit.state.phase, VendorProfilePhase.ready);
      expect(cubit.state.profile, aminaAdministratorProfile);
      expect(cubit.state.isFirstLoad, isFalse);

      repository.complete();
      await Future<void>.delayed(Duration.zero);
    });

    test('a failed refresh preserves the stale profile', () async {
      final VendorProfileCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();
      repository.result = unavailableProfileRead<VendorAdministratorProfile>();
      await cubit.refresh();

      expect(cubit.state.phase, VendorProfilePhase.failed);
      expect(cubit.state.failure, isA<UnavailableFailure>());
      // The profile stays. It is still the last thing the backend said.
      expect(cubit.state.profile, aminaAdministratorProfile);
      expect(cubit.state.isStale, isTrue);
      expect(cubit.state.hasFailedFirstRead, isFalse);
    });

    test('a denied refresh preserves the stale profile too', () async {
      final VendorProfileCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();
      repository.result = deniedProfileRead<VendorAdministratorProfile>();
      await cubit.refresh();

      expect(cubit.state.failure, isA<DeniedFailure>());
      expect(cubit.state.profile, aminaAdministratorProfile);
      expect(cubit.state.isStale, isTrue);
    });

    test('a failed refresh never empties the role list', () async {
      final VendorProfileCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();
      repository.result = unavailableProfileRead<VendorAdministratorProfile>();
      await cubit.refresh();

      expect(cubit.state.profile!.roleNames, <String>['Vendor Super Admin']);
      expect(cubit.state.profile!.displayName, 'Amina Rahman');
    });

    test('a retry after a failed refresh clears the notice', () async {
      final VendorProfileCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();
      repository.result = unavailableProfileRead<VendorAdministratorProfile>();
      await cubit.refresh();
      expect(cubit.state.isStale, isTrue);

      repository.result = null;
      await cubit.refresh();

      expect(cubit.state.phase, VendorProfilePhase.ready);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.isStale, isFalse);
    });

    test('a second refresh while one is in flight is a no-op', () async {
      repository.manual = true;
      final VendorProfileCubit cubit = buildCubit();
      addTearDown(cubit.close);

      unawaited(cubit.load());
      await Future<void>.delayed(Duration.zero);
      expect(repository.callCount, 1);

      unawaited(cubit.refresh());
      unawaited(cubit.refresh());
      await Future<void>.delayed(Duration.zero);

      // Still one. Two answers to the same question could arrive out of order
      // and leave the older one on screen.
      expect(repository.callCount, 1);
      expect(repository.pendingCount, 1);

      repository.complete();
      await Future<void>.delayed(Duration.zero);
    });

    test(
      'a refresh after the in-flight one settles does issue a call',
      () async {
        final VendorProfileCubit cubit = buildCubit();
        addTearDown(cubit.close);

        await cubit.load();
        await cubit.refresh();

        expect(repository.callCount, 2);
      },
    );

    test('a refresh with nothing loaded shows the loading state', () async {
      // A pull-to-refresh on a screen whose first read failed: there is nothing
      // on screen to preserve, so it behaves like a first read.
      repository.result = unavailableProfileRead<VendorAdministratorProfile>();
      final VendorProfileCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();
      repository.result = null;
      repository.manual = true;
      unawaited(cubit.refresh());
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, VendorProfilePhase.loading);
      expect(cubit.state.isFirstLoad, isTrue);

      repository.complete();
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('stale answers', () {
    test('a first read landing after a clear is ignored', () async {
      repository.manual = true;
      final VendorProfileCubit cubit = buildCubit();
      addTearDown(cubit.close);

      unawaited(cubit.load());
      await Future<void>.delayed(Duration.zero);

      cubit.clear();
      repository.complete();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.profile, isNull);
      expect(cubit.state.phase, VendorProfilePhase.initial);
    });

    test('a refresh landing after a clear is ignored', () async {
      final VendorProfileCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();
      repository.manual = true;
      unawaited(cubit.refresh());
      await Future<void>.delayed(Duration.zero);

      cubit.clear();
      repository.complete();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.profile, isNull);
      expect(cubit.state.phase, VendorProfilePhase.initial);
    });

    test('a failed read landing after a clear cannot set a failure', () async {
      repository.manual = true;
      final VendorProfileCubit cubit = buildCubit();
      addTearDown(cubit.close);

      unawaited(cubit.load());
      await Future<void>.delayed(Duration.zero);

      cubit.clear();
      repository.complete(unavailableProfileRead<VendorAdministratorProfile>());
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.failure, isNull);
      expect(cubit.state.phase, VendorProfilePhase.initial);
    });

    test('an older answer cannot overwrite a newer one', () async {
      repository.manual = true;
      final VendorProfileCubit cubit = buildCubit();
      addTearDown(cubit.close);

      unawaited(cubit.load());
      await Future<void>.delayed(Duration.zero);

      // A session change between the two: the token advances, and the second
      // read belongs to the new person.
      cubit.clear();
      unawaited(cubit.load());
      await Future<void>.delayed(Duration.zero);
      expect(repository.pendingCount, 2);

      // The newer answer settles first.
      repository.completeAt(
        1,
        const ReadSuccess<VendorAdministratorProfile>(joAdministratorProfile),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.profile, joAdministratorProfile);

      // The older one lands late and must be discarded — the previous
      // administrator's name under the new one's session would be a disclosure
      // dressed as a profile.
      repository.completeAt(
        0,
        const ReadSuccess<VendorAdministratorProfile>(
          aminaAdministratorProfile,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.profile, joAdministratorProfile);
    });
  });

  group('clearing', () {
    test('drops the profile, the failure and both flags', () async {
      final VendorProfileCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();
      repository.result = unavailableProfileRead<VendorAdministratorProfile>();
      await cubit.refresh();
      expect(cubit.state.isStale, isTrue);

      cubit.clear();

      expect(cubit.state, const VendorProfileState());
      expect(cubit.state.profile, isNull);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.isRefreshing, isFalse);
      expect(cubit.state.phase, VendorProfilePhase.initial);
    });

    test('the whole profile goes, not just the role list', () async {
      final VendorProfileCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();
      cubit.clear();

      expect(cubit.state.profile, isNull);
    });

    test('a load after a clear reads again', () async {
      final VendorProfileCubit cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.load();
      cubit.clear();
      await cubit.load();

      expect(repository.callCount, 2);
      expect(cubit.state.profile, aminaAdministratorProfile);
    });
  });

  group('the state exposes no per-field setter', () {
    test('copyWith replaces the profile whole', () {
      const VendorProfileState state = VendorProfileState(
        phase: VendorProfilePhase.ready,
        profile: aminaAdministratorProfile,
      );

      final VendorProfileState next = state.copyWith(
        profile: joAdministratorProfile,
      );

      expect(next.profile, joAdministratorProfile);
      // Not merged: both fields came from the new profile.
      expect(next.profile!.displayName, 'Jo Nakamura');
      expect(next.profile!.roleNames, hasLength(2));
    });

    test('equality is by phase, profile, failure and the refresh flag', () {
      const VendorProfileState a = VendorProfileState(
        phase: VendorProfilePhase.ready,
        profile: aminaAdministratorProfile,
      );
      const VendorProfileState b = VendorProfileState(
        phase: VendorProfilePhase.ready,
        profile: aminaAdministratorProfile,
      );

      expect(a, b);
      expect(a, isNot(b.copyWith(profile: joAdministratorProfile)));
      expect(a, isNot(b.copyWith(isRefreshing: true)));
    });

    test('the state holds no organization name of its own', () {
      // The company half of the screen belongs to the session. A cached copy
      // here would be a second source, free to go stale against the session that
      // owns it.
      const VendorProfileState state = VendorProfileState(
        phase: VendorProfilePhase.ready,
        profile: aminaAdministratorProfile,
      );

      expect(state.props, <Object?>[
        VendorProfilePhase.ready,
        aminaAdministratorProfile,
        null,
        false,
      ]);
      expect(state.toString(), isNot(contains('organization')));
    });
  });
}
