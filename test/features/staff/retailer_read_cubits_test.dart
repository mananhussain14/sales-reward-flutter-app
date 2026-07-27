import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/retailer_read_problem.dart';
import 'package:sale_reward/features/products/domain/repositories/retailer_product_repository.dart';
import 'package:sale_reward/features/products/presentation/retailer/cubit/retailer_products_cubit.dart';
import 'package:sale_reward/features/shops/domain/repositories/retailer_shop_repository.dart';
import 'package:sale_reward/features/shops/presentation/retailer_owner/cubit/retailer_shops_cubit.dart';
import 'package:sale_reward/features/staff/domain/repositories/retailer_staff_repository.dart';
import 'package:sale_reward/features/staff/presentation/retailer/cubit/retailer_staff_cubit.dart';

import '../../support/retailer_read_fakes.dart';

/// The three Retailer read cubits.
///
/// Grouped in one file because they answer the same questions — load once,
/// refresh in place, suppress duplicates, reject stale answers, clear on session
/// change — and the Staff cubit adds the one that is unique to it: two companion
/// sections whose outcomes must stay independent.
void main() {
  /// Lets a pending future settle without depending on a wall clock.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  // -------------------------------------------------------------------------
  group('shops', () {
    late FakeRetailerShopRepository repository;
    RetailerShopsCubit build() => RetailerShopsCubit(repository);

    setUp(() => repository = FakeRetailerShopRepository());

    test('load reads once and lands ready', () async {
      final RetailerShopsCubit cubit = build();
      await cubit.load();

      expect(repository.callCount, 1);
      expect(cubit.state.phase, RetailerShopsPhase.ready);
      expect(cubit.state.shops, exampleShops);
      await cubit.close();
    });

    test('loadOnce reads once however many times it is called', () async {
      // What makes "opening a tab reads once" and "returning to a loaded tab
      // reads nothing" both true without the page knowing which case it is in.
      final RetailerShopsCubit cubit = build();
      await cubit.loadOnce();
      await cubit.loadOnce();
      await cubit.loadOnce();

      expect(repository.callCount, 1);
      await cubit.close();
    });

    test('an empty estate is ready, not failed', () async {
      repository.nextShops = <dynamic>[].cast();
      final RetailerShopsCubit cubit = build();
      await cubit.load();

      expect(cubit.state.isEmpty, isTrue);
      expect(cubit.state.hasFailedOutright, isFalse);
      expect(cubit.state.problem, isNull);
      await cubit.close();
    });

    test(
      'refresh replaces the list and keeps rows on screen meanwhile',
      () async {
        repository.manual = true;
        final RetailerShopsCubit cubit = build();

        cubit.load();
        repository.complete();
        await settle();
        expect(cubit.state.shops, exampleShops);

        cubit.refresh();
        await settle();
        // The previous rows are still shown while the re-read runs.
        expect(cubit.state.shops, exampleShops);
        expect(cubit.state.isRefreshing, isTrue);
        expect(cubit.state.isInitialLoading, isFalse);

        repository.complete(RetailerShopsLoaded(otherShops));
        await settle();
        expect(cubit.state.shops, otherShops);
        await cubit.close();
      },
    );

    test('a duplicate refresh in flight issues no second call', () async {
      repository.manual = true;
      final RetailerShopsCubit cubit = build();

      cubit.load();
      await settle();
      cubit.refresh();
      cubit.refresh();
      await settle();

      expect(repository.callCount, 1);
      repository.complete();
      await settle();
      await cubit.close();
    });

    test('a failed refresh preserves prior data and marks it stale', () async {
      final RetailerShopsCubit cubit = build();
      await cubit.load();

      repository.result = const RetailerShopsFailed(
        RetailerReadProblem.network,
      );
      await cubit.refresh();

      expect(cubit.state.shops, exampleShops);
      expect(cubit.state.isStale, isTrue);
      expect(cubit.state.hasFailedOutright, isFalse);
      await cubit.close();
    });

    test('a failed first read holds no rows', () async {
      repository.result = const RetailerShopsFailed(
        RetailerReadProblem.malformed,
      );
      final RetailerShopsCubit cubit = build();
      await cubit.load();

      expect(cubit.state.hasFailedOutright, isTrue);
      expect(cubit.state.shops, isNull);
      // Never rendered as an empty estate.
      expect(cubit.state.isEmpty, isFalse);
      await cubit.close();
    });

    test('search filters locally and never issues a request', () async {
      final RetailerShopsCubit cubit = build();
      await cubit.load();
      final int before = repository.callCount;

      cubit.searchChanged('marina');
      expect(repository.callCount, before);
      expect(cubit.state.visibleShops, hasLength(1));
      expect(cubit.state.visibleShops.single.name, 'Northwind Marina');

      // Code and city match too.
      cubit.searchChanged('NW-02');
      expect(cubit.state.visibleShops.single.name, 'Northwind Downtown');
      cubit.searchChanged('abu dhabi');
      expect(cubit.state.visibleShops.single.name, 'Northwind Downtown');
      await cubit.close();
    });

    test(
      'a search that hides everything is distinct from an empty estate',
      () async {
        final RetailerShopsCubit cubit = build();
        await cubit.load();
        cubit.searchChanged('zzzz');

        expect(cubit.state.isSearchEmpty, isTrue);
        expect(cubit.state.isEmpty, isFalse);
        await cubit.close();
      },
    );

    test(
      'clear empties rows, search and problem, and drops a stale answer',
      () async {
        repository.manual = true;
        final RetailerShopsCubit cubit = build();

        cubit.load();
        await settle();
        cubit.searchChanged('marina');

        cubit.clear();
        expect(cubit.state, const RetailerShopsState());
        expect(cubit.state.searchTerm, isEmpty);

        // The previous identity's answer lands now and must be ignored.
        repository.complete();
        await settle();
        expect(cubit.state.shops, isNull);
        expect(cubit.state.phase, RetailerShopsPhase.initial);
        await cubit.close();
      },
    );

    test('after clear, loadOnce reads again', () async {
      final RetailerShopsCubit cubit = build();
      await cubit.loadOnce();
      cubit.clear();
      await cubit.loadOnce();

      expect(repository.callCount, 2);
      await cubit.close();
    });
  });

  // -------------------------------------------------------------------------
  group('products', () {
    late FakeRetailerProductRepository repository;
    RetailerProductsCubit build() => RetailerProductsCubit(repository);

    setUp(() => repository = FakeRetailerProductRepository());

    test('load reads once and lands ready', () async {
      final RetailerProductsCubit cubit = build();
      await cubit.load();

      expect(repository.callCount, 1);
      expect(cubit.state.products, exampleAssignedProducts);
      await cubit.close();
    });

    test('a denial is never an empty catalogue', () async {
      repository.result = const RetailerProductsFailed(
        RetailerReadProblem.denied,
      );
      final RetailerProductsCubit cubit = build();
      await cubit.load();

      expect(cubit.state.hasFailedOutright, isTrue);
      expect(cubit.state.isEmpty, isFalse);
      expect(cubit.state.problem, RetailerReadProblem.denied);
      await cubit.close();
    });

    test('search matches name, code, brand and barcode', () async {
      final RetailerProductsCubit cubit = build();
      await cubit.load();

      for (final String term in <String>[
        'espresso',
        'ESP-1000',
        'aurora',
        '5012345678900',
      ]) {
        cubit.searchChanged(term);
        expect(
          cubit.state.visibleProducts.single.productCode,
          'ESP-1000',
          reason: term,
        );
      }
      expect(repository.callCount, 1);
      await cubit.close();
    });

    test('a stale answer cannot repopulate a cleared catalogue', () async {
      repository.manual = true;
      final RetailerProductsCubit cubit = build();

      cubit.load();
      await settle();
      cubit.clear();
      repository.complete();
      await settle();

      expect(cubit.state.products, isNull);
      await cubit.close();
    });

    test('an out-of-order answer cannot overwrite a newer one', () async {
      repository.manual = true;
      final RetailerProductsCubit cubit = build();

      cubit.load();
      await settle();
      cubit.clear();
      cubit.load();
      await settle();
      expect(repository.pendingCount, 2);

      // Complete the OLD request first.
      repository.completeAt(0, RetailerProductsLoaded(otherAssignedProducts));
      await settle();
      expect(cubit.state.products, isNull);

      // Then the current one.
      repository.completeAt(0, RetailerProductsLoaded(exampleAssignedProducts));
      await settle();
      expect(cubit.state.products, exampleAssignedProducts);
      await cubit.close();
    });
  });

  // -------------------------------------------------------------------------
  group('staff', () {
    late FakeRetailerStaffRepository repository;
    RetailerStaffCubit build({bool invitations = true}) =>
        RetailerStaffCubit(repository, includeInvitations: invitations);

    setUp(() => repository = FakeRetailerStaffRepository());

    test('the Owner view reads both sections', () async {
      final RetailerStaffCubit cubit = build();
      await cubit.load();

      expect(repository.memberCallCount, 1);
      expect(repository.invitationCallCount, 1);
      expect(cubit.state.members, exampleStaff);
      expect(cubit.state.invitations, exampleInvitations);
      expect(cubit.state.showsInvitations, isTrue);
      await cubit.close();
    });

    test('the Manager view never calls the invitation RPC', () async {
      // Its only possible outcome for a Manager is 42501, which would put a
      // denial notice on a screen where nothing is wrong.
      final RetailerStaffCubit cubit = build(invitations: false);
      await cubit.load();

      expect(repository.memberCallCount, 1);
      expect(repository.invitationCallCount, 0);
      expect(cubit.state.showsInvitations, isFalse);
      expect(cubit.state.invitationPhase, RetailerStaffPhase.notApplicable);
      // Not an error and not an empty list — the section does not apply.
      expect(cubit.state.invitationProblem, isNull);
      expect(cubit.state.invitations, isNull);
      await cubit.close();
    });

    test('a failed invitation read never erases a good roster', () async {
      // The partial-success case the screen must not describe as
      // "everything failed".
      repository.invitationsResult = const RetailerInvitationsFailed(
        RetailerReadProblem.denied,
      );
      final RetailerStaffCubit cubit = build();
      await cubit.load();

      expect(cubit.state.members, exampleStaff);
      expect(cubit.state.rosterPhase, RetailerStaffPhase.ready);
      expect(cubit.state.hasInvitationsFailedOutright, isTrue);
      expect(cubit.state.isPartialSuccess, isTrue);
      // The roster's own problem is untouched.
      expect(cubit.state.rosterProblem, isNull);
      await cubit.close();
    });

    test(
      'a failed roster read never erases a good invitation history',
      () async {
        repository.rosterResult = const RetailerStaffFailed(
          RetailerReadProblem.timeout,
        );
        final RetailerStaffCubit cubit = build();
        await cubit.load();

        expect(cubit.state.invitations, exampleInvitations);
        expect(cubit.state.hasRosterFailedOutright, isTrue);
        expect(cubit.state.isPartialSuccess, isTrue);
        expect(cubit.state.invitationProblem, isNull);
        await cubit.close();
      },
    );

    test('both failing is not reported as partial success', () async {
      repository.rosterResult = const RetailerStaffFailed(
        RetailerReadProblem.network,
      );
      repository.invitationsResult = const RetailerInvitationsFailed(
        RetailerReadProblem.network,
      );
      final RetailerStaffCubit cubit = build();
      await cubit.load();

      expect(cubit.state.isPartialSuccess, isFalse);
      expect(cubit.state.hasRosterFailedOutright, isTrue);
      expect(cubit.state.hasInvitationsFailedOutright, isTrue);
      await cubit.close();
    });

    test('a successful refresh clears a previous section problem', () async {
      repository.invitationsResult = const RetailerInvitationsFailed(
        RetailerReadProblem.network,
      );
      final RetailerStaffCubit cubit = build();
      await cubit.load();
      expect(cubit.state.invitationProblem, isNotNull);

      repository.invitationsResult = null;
      await cubit.refresh();

      expect(cubit.state.invitationProblem, isNull);
      expect(cubit.state.invitations, exampleInvitations);
      await cubit.close();
    });

    test('loadOnce reads once however many times it is called', () async {
      final RetailerStaffCubit cubit = build();
      await cubit.loadOnce();
      await cubit.loadOnce();

      expect(repository.memberCallCount, 1);
      expect(repository.invitationCallCount, 1);
      await cubit.close();
    });

    test('one search term filters both sections', () async {
      final RetailerStaffCubit cubit = build();
      await cubit.load();

      cubit.searchChanged('lena');
      expect(cubit.state.visibleMembers, isEmpty);
      expect(cubit.state.visibleInvitations, hasLength(1));

      cubit.searchChanged('priya');
      expect(cubit.state.visibleMembers, hasLength(1));
      expect(cubit.state.visibleInvitations, isEmpty);

      // Shop name matches the roster.
      cubit.searchChanged('marina');
      expect(cubit.state.visibleMembers, isNotEmpty);
      await cubit.close();
    });

    test('search never matches the internal role code', () async {
      // `roleCode` is never displayed, so matching it would surface rows for a
      // reason the user cannot see.
      final RetailerStaffCubit cubit = build();
      await cubit.load();

      cubit.searchChanged('SALES_STAFF');
      expect(cubit.state.visibleMembers, isEmpty);
      // The display name still matches.
      cubit.searchChanged('Sales Staff');
      expect(cubit.state.visibleMembers, isNotEmpty);
      await cubit.close();
    });

    test('clear empties both sections, the search and both problems', () async {
      final RetailerStaffCubit cubit = build();
      await cubit.load();
      cubit.searchChanged('priya');

      cubit.clear();

      expect(cubit.state, const RetailerStaffState());
      expect(cubit.state.members, isNull);
      expect(cubit.state.invitations, isNull);
      expect(cubit.state.searchTerm, isEmpty);
      await cubit.close();
    });

    test('stale answers for either section are dropped after clear', () async {
      repository.manual = true;
      final RetailerStaffCubit cubit = build();

      cubit.load();
      await settle();
      cubit.clear();

      repository.completeMembers();
      repository.completeInvitations();
      await settle();

      expect(cubit.state.members, isNull);
      expect(cubit.state.invitations, isNull);
      await cubit.close();
    });

    test(
      'a duplicate refresh in flight issues no second pair of calls',
      () async {
        repository.manual = true;
        final RetailerStaffCubit cubit = build();

        cubit.load();
        await settle();
        cubit.refresh();
        cubit.refresh();
        await settle();

        expect(repository.memberCallCount, 1);
        expect(repository.invitationCallCount, 1);
        repository.completeMembers();
        repository.completeInvitations();
        await settle();
        await cubit.close();
      },
    );
  });

  // -------------------------------------------------------------------------
  group('tabs are independent', () {
    test('reading one tab does not read another', () async {
      final FakeRetailerShopRepository shops = FakeRetailerShopRepository();
      final FakeRetailerStaffRepository staff = FakeRetailerStaffRepository();
      final FakeRetailerProductRepository products =
          FakeRetailerProductRepository();

      final RetailerShopsCubit shopsCubit = RetailerShopsCubit(shops);
      final RetailerStaffCubit staffCubit = RetailerStaffCubit(
        staff,
        includeInvitations: true,
      );
      final RetailerProductsCubit productsCubit = RetailerProductsCubit(
        products,
      );

      await shopsCubit.loadOnce();

      expect(shops.callCount, 1);
      expect(staff.memberCallCount, 0);
      expect(staff.invitationCallCount, 0);
      expect(products.callCount, 0);

      await shopsCubit.close();
      await staffCubit.close();
      await productsCubit.close();
    });
  });
}
