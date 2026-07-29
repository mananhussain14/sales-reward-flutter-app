import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/shells/retailer_manager/retailer_manager_navigation.dart';
import 'package:sale_reward/app/shells/retailer_owner/retailer_owner_navigation.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_navigation.dart';
import 'package:sale_reward/app/shells/vendor/vendor_navigation.dart';
import 'package:sale_reward/core/errors/retailer_read_problem.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/auth/domain/entities/auth_user.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/dashboard/presentation/retailer_owner/pages/retailer_owner_overview_page.dart';
import 'package:sale_reward/features/products/domain/repositories/retailer_product_repository.dart';
import 'package:sale_reward/features/products/presentation/retailer/pages/retailer_products_page.dart';
import 'package:sale_reward/features/products/presentation/retailer/widgets/retailer_product_card.dart';
import 'package:sale_reward/features/products/presentation/retailer/widgets/retailer_products_copy.dart';
import 'package:sale_reward/features/shops/domain/repositories/retailer_shop_repository.dart';
import 'package:sale_reward/features/shops/presentation/retailer_owner/pages/retailer_owner_shops_page.dart';
import 'package:sale_reward/features/shops/presentation/retailer_owner/widgets/retailer_shop_card.dart';
import 'package:sale_reward/features/shops/presentation/retailer_owner/widgets/retailer_shops_copy.dart';
import 'package:sale_reward/features/staff/domain/repositories/retailer_staff_repository.dart';
import 'package:sale_reward/features/staff/presentation/retailer/pages/retailer_staff_page.dart';
import 'package:sale_reward/features/staff/presentation/retailer/widgets/retailer_invitation_card.dart';
import 'package:sale_reward/features/staff/presentation/retailer/widgets/retailer_invite_staff_form.dart';
import 'package:sale_reward/features/staff/presentation/retailer/widgets/retailer_staff_copy.dart';
import 'package:sale_reward/features/staff/presentation/retailer/widgets/retailer_staff_member_card.dart';

import '../../support/fakes.dart';
import '../../support/pump_app.dart';
import '../../support/retailer_read_fakes.dart';

/// Drives the three Retailer read screens through the real application: real
/// router, real shells, real cubits, over fakes that never touch Supabase.
void main() {
  Future<void> unmountApp(WidgetTester tester) async {
    // `SaleRewardApp` carries no key, so a second `pumpWidget` of the same type
    // reuses the existing `State` — and with it the first pump's repositories.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  /// Scrolls [finder] into view before tapping.
  ///
  /// A control at the bottom of a long page sits below the fold on a phone, and
  /// a blind `tap` there lands on whatever is painted at those coordinates —
  /// the bottom navigation bar. The same helper exists in the Vendor flow tests
  /// for the same reason.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> goTo(WidgetTester tester, String location) async {
    GoRouter.of(tester.element(find.byType(Navigator).first)).go(location);
    await tester.pumpAndSettle();
  }

  String currentLocation(WidgetTester tester) => GoRouter.of(
    tester.element(find.byType(Navigator).first),
  ).routeInformationProvider.value.uri.path;

  Finder semanticsContaining(String fragment) => find.byWidgetPredicate(
    (Widget widget) =>
        widget is Semantics &&
        (widget.properties.label?.contains(fragment) ?? false),
    description: 'Semantics whose label contains "$fragment"',
  );

  // -------------------------------------------------------------------------
  group('routing', () {
    testWidgets('the Owner reaches all four destinations', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerOwner);
      expect(find.byType(RetailerOwnerOverviewPage), findsOneWidget);

      await goTo(tester, RetailerOwnerNavigation.shops);
      expect(find.byType(RetailerOwnerShopsPage), findsOneWidget);

      await goTo(tester, RetailerOwnerNavigation.staff);
      expect(find.byType(RetailerStaffPage), findsOneWidget);

      await goTo(tester, RetailerOwnerNavigation.products);
      expect(find.byType(RetailerProductsPage), findsOneWidget);
    });

    testWidgets('the Manager reaches Staff and Products only', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerManager);
      expect(currentLocation(tester), RetailerManagerNavigation.staff);
      expect(find.byType(RetailerStaffPage), findsOneWidget);

      await goTo(tester, RetailerManagerNavigation.products);
      expect(find.byType(RetailerProductsPage), findsOneWidget);
    });

    testWidgets('the Manager cannot enter the Owner Overview', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.retailerManager,
      );

      await goTo(tester, RetailerOwnerNavigation.overview);

      expect(currentLocation(tester), RetailerManagerNavigation.staff);
      expect(find.byType(RetailerOwnerOverviewPage), findsNothing);
      expect(app.retailerOverview.callCount, 0);
    });

    testWidgets('the Manager has no Shops route and cannot reach one', (
      WidgetTester tester,
    ) async {
      // `list_retailer_owner_portal_shops()` uses the Owner-only resolver and
      // returns an EMPTY LIST rather than raising, so a Manager would see an
      // empty estate indistinguishable from a Retailer that has none. The route
      // does not exist for this role, and the read is never issued.
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.retailerManager,
      );

      await goTo(tester, RetailerOwnerNavigation.shops);

      expect(currentLocation(tester), RetailerManagerNavigation.staff);
      expect(find.byType(RetailerOwnerShopsPage), findsNothing);
      expect(app.retailerShops.callCount, 0);
    });

    testWidgets('the Manager navigation carries no Shops destination', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerManager);

      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Shops'),
        ),
        findsNothing,
      );
    });

    testWidgets('Sales Staff routing is unchanged and reads nothing', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await pumpAppInRole(tester, PortalKind.salesStaff);

      expect(currentLocation(tester), SalesStaffNavigation.submit);
      expect(app.retailerShops.callCount, 0);
      expect(app.retailerStaff.memberCallCount, 0);
      expect(app.retailerProducts.callCount, 0);
    });

    testWidgets('Vendor routing is unchanged and reads nothing', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.vendorSuperAdmin,
        surface: desktopSurface,
      );

      expect(currentLocation(tester), VendorNavigation.dashboard);
      expect(app.retailerShops.callCount, 0);
      expect(app.retailerStaff.memberCallCount, 0);
      expect(app.retailerProducts.callCount, 0);
    });
  });

  // -------------------------------------------------------------------------
  group('independent tab loading', () {
    testWidgets('entering the shell reads only the Overview', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
      );

      expect(app.retailerOverview.callCount, 1);
      expect(app.retailerShops.callCount, 0);
      expect(app.retailerStaff.memberCallCount, 0);
      expect(app.retailerProducts.callCount, 0);
    });

    testWidgets('opening Shops reads Shops and nothing else', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
      );
      await goTo(tester, RetailerOwnerNavigation.shops);

      expect(app.retailerShops.callCount, 1);
      expect(app.retailerStaff.memberCallCount, 0);
      expect(app.retailerProducts.callCount, 0);
      // And the Overview is not re-read.
      expect(app.retailerOverview.callCount, 1);
    });

    testWidgets('returning to a loaded tab does not re-read it', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
      );

      await goTo(tester, RetailerOwnerNavigation.shops);
      expect(app.retailerShops.callCount, 1);

      await goTo(tester, RetailerOwnerNavigation.products);
      await goTo(tester, RetailerOwnerNavigation.shops);

      expect(app.retailerShops.callCount, 1);
      expect(app.retailerProducts.callCount, 1);
    });
  });

  // -------------------------------------------------------------------------
  group('shops screen', () {
    Future<PumpedApp> onShops(
      WidgetTester tester, {
      FakeRetailerShopRepository? shops,
      Size surface = phoneSurface,
    }) async {
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        surface: surface,
        retailerShops: shops,
      );
      await goTo(tester, RetailerOwnerNavigation.shops);
      return app;
    }

    testWidgets('renders every shop with its fields', (
      WidgetTester tester,
    ) async {
      await onShops(tester);

      expect(find.byType(RetailerShopCard), findsNWidgets(3));
      expect(find.text('Northwind Marina'), findsOneWidget);
      expect(find.text('NW-01'), findsOneWidget);
      expect(find.text('Dubai'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Suspended'), findsOneWidget);
      expect(find.text('Deactivated'), findsOneWidget);
    });

    testWidgets('no row is tappable and no write control exists', (
      WidgetTester tester,
    ) async {
      await onShops(tester);

      // The card renders no ink response, so nothing invites a tap.
      expect(
        find.descendant(
          of: find.byType(RetailerShopCard),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
      for (final IconData icon in <IconData>[
        Icons.chevron_right,
        Icons.chevron_right_rounded,
        Icons.edit,
        Icons.edit_rounded,
        Icons.add,
        Icons.delete_outline,
      ]) {
        expect(find.byIcon(icon), findsNothing, reason: icon.toString());
      }
      expect(find.textContaining('View details'), findsNothing);
    });

    testWidgets('a shop with only a name omits the absent fields', (
      WidgetTester tester,
    ) async {
      await onShops(tester);
      // The warehouse row has no code, city or country — and no placeholder is
      // rendered for them.
      expect(find.text('Northwind Warehouse'), findsOneWidget);
      expect(find.text('—'), findsNothing);
    });

    testWidgets('an empty estate shows its own state, and hides search', (
      WidgetTester tester,
    ) async {
      final FakeRetailerShopRepository repo = FakeRetailerShopRepository()
        ..nextShops = const <Never>[];
      await onShops(tester, shops: repo);

      expect(find.text(RetailerShopsCopy.emptyTitle), findsOneWidget);
      expect(find.byType(RetailerShopCard), findsNothing);
      expect(find.byType(SrSearchField), findsNothing);
    });

    testWidgets('local search filters and can be cleared', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onShops(tester);

      await tester.enterText(find.byType(TextField).first, 'marina');
      await tester.pumpAndSettle();

      expect(find.byType(RetailerShopCard), findsOneWidget);
      expect(find.text('Showing 1 of 3'), findsOneWidget);
      // No request was issued for the search.
      expect(app.retailerShops.callCount, 1);

      await tester.enterText(find.byType(TextField).first, 'zzzz');
      await tester.pumpAndSettle();
      expect(find.text(RetailerShopsCopy.searchEmptyTitle), findsOneWidget);

      await tapVisible(tester, find.text('Clear search'));
      expect(find.byType(RetailerShopCard), findsNWidgets(3));
    });

    testWidgets('refresh re-reads', (WidgetTester tester) async {
      final PumpedApp app = await onShops(tester);

      app.retailerShops.nextShops = otherShops;
      await tapVisible(tester, find.text(RetailerShopsCopy.refresh));

      expect(app.retailerShops.callCount, 2);
      expect(find.text('Southgate Central'), findsOneWidget);
      expect(find.text('Northwind Marina'), findsNothing);
    });

    testWidgets('a failure offers a retry that re-reads', (
      WidgetTester tester,
    ) async {
      final FakeRetailerShopRepository repo = FakeRetailerShopRepository()
        ..result = const RetailerShopsFailed(RetailerReadProblem.network);
      await onShops(tester, shops: repo);

      expect(find.text('Could not reach SalesReward'), findsOneWidget);
      expect(find.byType(RetailerShopCard), findsNothing);

      repo.result = null;
      await tapVisible(tester, find.text('Try again'));

      expect(repo.callCount, 2);
      expect(find.byType(RetailerShopCard), findsNWidgets(3));
    });

    testWidgets('a denial offers no retry', (WidgetTester tester) async {
      final FakeRetailerShopRepository repo = FakeRetailerShopRepository()
        ..result = const RetailerShopsFailed(RetailerReadProblem.denied);
      await onShops(tester, shops: repo);

      expect(find.text('Not available to this account'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });

    for (final (String name, Size surface) in <(String, Size)>[
      ('a small Android phone', smallPhoneSurface),
      ('a phone', phoneSurface),
      ('a desktop browser', desktopSurface),
    ]) {
      testWidgets('$name lays out without overflowing', (
        WidgetTester tester,
      ) async {
        await onShops(tester, surface: surface);
        expect(find.byType(RetailerOwnerShopsPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('each card is one readable sentence', (
      WidgetTester tester,
    ) async {
      await onShops(tester);
      expect(semanticsContaining('Northwind Marina. Active.'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('staff screen — Owner', () {
    Future<PumpedApp> onStaff(
      WidgetTester tester, {
      FakeRetailerStaffRepository? staff,
      Size surface = phoneSurface,
    }) async {
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        surface: surface,
        retailerStaff: staff,
      );
      await goTo(tester, RetailerOwnerNavigation.staff);
      return app;
    }

    testWidgets('shows both sections', (WidgetTester tester) async {
      final PumpedApp app = await onStaff(tester);

      expect(find.text(RetailerStaffCopy.rosterTitle), findsOneWidget);
      expect(find.text(RetailerStaffCopy.invitationsTitle), findsOneWidget);
      expect(app.retailerStaff.memberCallCount, 1);
      expect(app.retailerStaff.invitationCallCount, 1);
    });

    testWidgets('roster rows show name, role, status, shops and joined', (
      WidgetTester tester,
    ) async {
      await onStaff(tester);

      expect(find.text('Priya Raman'), findsOneWidget);
      expect(find.text('Sales Staff'), findsWidgets);
      expect(find.text('Northwind Marina'), findsWidgets);
      expect(find.textContaining('Joined: 12 Apr 2026'), findsOneWidget);
    });

    testWidgets('a member with no shops says so rather than showing a gap', (
      WidgetTester tester,
    ) async {
      await onStaff(tester);
      expect(find.text(RetailerStaffCopy.noShopsLabel), findsWidgets);
    });

    testWidgets('a member who never joined shows an absence, not a date', (
      WidgetTester tester,
    ) async {
      await onStaff(tester);
      expect(
        find.textContaining('Joined: ${RetailerStaffCopy.joinedUnknown}'),
        findsOneWidget,
      );
    });

    testWidgets('invitation rows show the safe labels', (
      WidgetTester tester,
    ) async {
      await onStaff(tester);

      expect(find.byType(RetailerInvitationCard), findsNWidgets(4));
      expect(find.text('lena@example.com'), findsOneWidget);
      expect(find.text('Awaiting acceptance'), findsOneWidget);
      expect(find.text('Accepted'), findsWidgets);
      // The NULL derived_state renders neutrally rather than being hidden.
      expect(find.text('Status unavailable'), findsOneWidget);
    });

    testWidgets('a delivery failure shows safe copy and no raw code', (
      WidgetTester tester,
    ) async {
      await onStaff(tester);

      expect(find.text(RetailerStaffCopy.deliveryFailedLabel), findsOneWidget);
      expect(find.textContaining('EMAIL_DISPATCH'), findsNothing);
      expect(find.textContaining('failure_code'), findsNothing);
    });

    testWidgets('the intended role is a label, never a raw code', (
      WidgetTester tester,
    ) async {
      await onStaff(tester);

      expect(find.textContaining('Invited as: Sales Staff'), findsWidgets);
      expect(find.textContaining('SALES_STAFF'), findsNothing);
      expect(find.textContaining('RETAILER_MANAGER'), findsNothing);
    });

    testWidgets('the only invitation write is sending a new one', (
      WidgetTester tester,
    ) async {
      await onStaff(tester);

      // Sending is this milestone's one write, and it lives in the Owner-only
      // form above the history.
      expect(find.byType(RetailerInviteStaffForm), findsOneWidget);

      // Everything else an INVITATION could be done to is still absent — not
      // disabled, absent. Each is a separate backend operation this app does
      // not perform, and acceptance happens in the emailed link rather than
      // here.
      //
      // `Deactivate` / `Reactivate` are deliberately NOT in this list any more.
      // They are not invitation writes: they act on an already accepted
      // MEMBERSHIP, through `set_retailer_staff_membership_status` on a
      // different permission, and they arrived with the staff lifecycle
      // milestone. Their placement and their exclusions are asserted by
      // `retailer_staff_lifecycle_flow_test.dart` and
      // `retailer_staff_lifecycle_boundary_test.dart`; what this test still
      // guarantees is that no such control reaches an *invitation* row, which
      // the assertion below states directly.
      for (final String label in <String>[
        'Resend',
        'Revoke',
        'Accept',
        'Change role',
        'Reassign shops',
      ]) {
        expect(find.text(label), findsNothing, reason: label);
      }

      // No lifecycle control on any invitation card. An invitation is not a
      // membership, and the RPC refuses an INVITED target outright.
      for (final String label in <String>['Deactivate', 'Reactivate']) {
        expect(
          find.descendant(
            of: find.byType(RetailerInvitationCard),
            matching: find.text(label),
          ),
          findsNothing,
          reason: '$label must never appear on an invitation',
        );
      }
      expect(find.byIcon(Icons.add), findsNothing);
    });

    testWidgets('a failed invitation read keeps the roster on screen', (
      WidgetTester tester,
    ) async {
      // The partial-success case: one section failed, and the screen must not
      // claim both did.
      final FakeRetailerStaffRepository repo = FakeRetailerStaffRepository()
        ..invitationsResult = const RetailerInvitationsFailed(
          RetailerReadProblem.denied,
        );
      await onStaff(tester, staff: repo);

      expect(find.byType(RetailerStaffMemberCard), findsWidgets);
      expect(find.text('Priya Raman'), findsOneWidget);
      expect(find.text('Not available to this account'), findsOneWidget);
      // The roster section header is still there — it did not fail.
      expect(find.text(RetailerStaffCopy.rosterTitle), findsOneWidget);
    });

    testWidgets('a failed roster read keeps the invitations on screen', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffRepository repo = FakeRetailerStaffRepository()
        ..rosterResult = const RetailerStaffFailed(RetailerReadProblem.timeout);
      await onStaff(tester, staff: repo);

      expect(find.byType(RetailerInvitationCard), findsWidgets);
      expect(find.text('This took too long'), findsOneWidget);
    });

    testWidgets('search filters both sections', (WidgetTester tester) async {
      await onStaff(tester);

      // Addressed through the search field itself rather than by position:
      // the Owner's Invite Staff form sits above it and owns the first three
      // text fields on the screen.
      await tester.enterText(
        find.descendant(
          of: find.byType(SrSearchField),
          matching: find.byType(TextField),
        ),
        'lena',
      );
      await tester.pumpAndSettle();

      expect(find.byType(RetailerStaffMemberCard), findsNothing);
      expect(find.byType(RetailerInvitationCard), findsOneWidget);
    });

    testWidgets('refresh re-reads both sections', (WidgetTester tester) async {
      final PumpedApp app = await onStaff(tester);

      await tapVisible(tester, find.text(RetailerStaffCopy.refresh));

      expect(app.retailerStaff.memberCallCount, 2);
      expect(app.retailerStaff.invitationCallCount, 2);
    });

    for (final (String name, Size surface) in <(String, Size)>[
      ('a small Android phone', smallPhoneSurface),
      ('a desktop browser', desktopSurface),
    ]) {
      testWidgets('$name lays out without overflowing', (
        WidgetTester tester,
      ) async {
        await onStaff(tester, surface: surface);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // -------------------------------------------------------------------------
  group('staff screen — Manager', () {
    Future<PumpedApp> onManagerStaff(WidgetTester tester) async {
      final FakeRetailerStaffRepository repo = FakeRetailerStaffRepository()
        ..nextMembers = managerVisibleStaff;
      return pumpAppInRole(
        tester,
        PortalKind.retailerManager,
        retailerStaff: repo,
      );
    }

    testWidgets('shows the roster and never the invitation history', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onManagerStaff(tester);

      expect(find.byType(RetailerStaffMemberCard), findsWidgets);
      expect(find.text(RetailerStaffCopy.invitationsTitle), findsNothing);
      expect(find.byType(RetailerInvitationCard), findsNothing);
      // The RPC that would refuse them is never called.
      expect(app.retailerStaff.invitationCallCount, 0);
    });

    testWidgets('shows only the members the backend returned', (
      WidgetTester tester,
    ) async {
      await onManagerStaff(tester);

      // The suspended member is absent because SQL did not return them — the
      // client applies no filter of its own.
      expect(find.text('Tom Byrne'), findsNothing);
      expect(find.text('Priya Raman'), findsOneWidget);
    });

    testWidgets('uses polished user-facing copy, not internal wording', (
      WidgetTester tester,
    ) async {
      await onManagerStaff(tester);

      expect(find.text(RetailerStaffCopy.managerScopeNote), findsOneWidget);
      // The old placeholder wording is gone.
      expect(find.textContaining('not connected to Supabase'), findsNothing);
      expect(find.textContaining('build'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  group('products screen', () {
    Future<PumpedApp> onProducts(
      WidgetTester tester, {
      FakeRetailerProductRepository? products,
      PortalKind role = PortalKind.retailerOwner,
      Size surface = phoneSurface,
    }) async {
      final PumpedApp app = await pumpAppInRole(
        tester,
        role,
        surface: surface,
        retailerProducts: products,
      );
      await goTo(
        tester,
        role == PortalKind.retailerOwner
            ? RetailerOwnerNavigation.products
            : RetailerManagerNavigation.products,
      );
      return app;
    }

    testWidgets('renders products with their fields', (
      WidgetTester tester,
    ) async {
      await onProducts(tester);

      expect(find.byType(RetailerProductCard), findsNWidgets(2));
      expect(find.text('Espresso Blend 1kg'), findsOneWidget);
      expect(find.text('ESP-1000'), findsOneWidget);
      expect(find.text('Aurora'), findsOneWidget);
      expect(find.text('5012345678900'), findsOneWidget);
      expect(
        find.text('A dark roast blend for espresso machines.'),
        findsOneWidget,
      );
    });

    testWidgets('the Manager sees the identical screen', (
      WidgetTester tester,
    ) async {
      await onProducts(tester, role: PortalKind.retailerManager);

      expect(find.byType(RetailerProductCard), findsNWidgets(2));
      expect(find.text('Espresso Blend 1kg'), findsOneWidget);
    });

    testWidgets('no write control and no assignment status badge', (
      WidgetTester tester,
    ) async {
      await onProducts(tester);

      for (final String label in <String>[
        'Assign',
        'Withdraw',
        'Edit',
        'Remove',
        'Add product',
      ]) {
        expect(find.text(label), findsNothing, reason: label);
      }
      // 'ACTIVE' is constant on this contract, so no badge repeats it.
      expect(find.text('ACTIVE'), findsNothing);
    });

    testWidgets(
      'the note says assignments are the Vendor\'s and current-only',
      (WidgetTester tester) async {
        await onProducts(tester);
        expect(find.text(RetailerProductsCopy.readOnlyNote), findsOneWidget);
      },
    );

    testWidgets('an empty catalogue shows its own state', (
      WidgetTester tester,
    ) async {
      final FakeRetailerProductRepository repo = FakeRetailerProductRepository()
        ..nextProducts = const <Never>[];
      await onProducts(tester, products: repo);

      expect(find.text(RetailerProductsCopy.emptyTitle), findsOneWidget);
      expect(find.byType(RetailerProductCard), findsNothing);
    });

    testWidgets('search filters locally', (WidgetTester tester) async {
      final PumpedApp app = await onProducts(tester);

      await tester.enterText(find.byType(TextField).first, 'green');
      await tester.pumpAndSettle();

      expect(find.byType(RetailerProductCard), findsOneWidget);
      expect(find.text('Green Tea 500g'), findsOneWidget);
      expect(app.retailerProducts.callCount, 1);
    });

    testWidgets('refresh re-reads', (WidgetTester tester) async {
      final PumpedApp app = await onProducts(tester);

      app.retailerProducts.nextProducts = otherAssignedProducts;
      await tapVisible(tester, find.text(RetailerProductsCopy.refresh));

      expect(app.retailerProducts.callCount, 2);
      expect(find.text('Dark Chocolate 200g'), findsOneWidget);
    });

    testWidgets('a malformed response is not shown as a connection problem', (
      WidgetTester tester,
    ) async {
      final FakeRetailerProductRepository repo = FakeRetailerProductRepository()
        ..result = const RetailerProductsFailed(RetailerReadProblem.malformed);
      await onProducts(tester, products: repo);

      expect(find.text('Could not read this'), findsOneWidget);
      expect(find.textContaining('Check your connection'), findsNothing);
      expect(find.byType(RetailerProductCard), findsNothing);
    });

    for (final (String name, Size surface) in <(String, Size)>[
      ('a small Android phone', smallPhoneSurface),
      ('a desktop browser', desktopSurface),
    ]) {
      testWidgets('$name lays out without overflowing', (
        WidgetTester tester,
      ) async {
        await onProducts(tester, surface: surface);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // -------------------------------------------------------------------------
  group('session isolation', () {
    const AuthUser secondUser = AuthUser(id: 'user-2', email: 'b@example.com');

    testWidgets('Retailer Owner A to Retailer Owner B clears every tab', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
      );
      await goTo(tester, RetailerOwnerNavigation.shops);
      expect(find.text('Northwind Marina'), findsOneWidget);

      app.retailerShops.nextShops = otherShops;
      app.portal.result = otherRetailerOwnerResult();
      app.auth.emitSignedIn(secondUser);
      await tester.pumpAndSettle();

      expect(find.text('Northwind Marina'), findsNothing);
      expect(find.text('NW-01'), findsNothing);
    });

    testWidgets('a search term does not survive a session change', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
      );
      await goTo(tester, RetailerOwnerNavigation.shops);
      await tester.enterText(find.byType(TextField).first, 'marina');
      await tester.pumpAndSettle();
      expect(find.text('Showing 1 of 3'), findsOneWidget);

      app.portal.result = otherRetailerOwnerResult();
      app.auth.emitSignedIn(secondUser);
      await tester.pumpAndSettle();

      expect(find.text('Showing 1 of 3'), findsNothing);
    });

    testWidgets('Retailer Owner to Retailer Manager leaves nothing behind', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
      );
      await goTo(tester, RetailerOwnerNavigation.staff);
      expect(find.text('Tom Byrne'), findsOneWidget);

      app.retailerStaff.nextMembers = managerVisibleStaff;
      app.portal.result = resolvedResult(PortalKind.retailerManager);
      app.auth.emitSignedIn(secondUser);
      await tester.pumpAndSettle();

      expect(currentLocation(tester), RetailerManagerNavigation.staff);
      // The Owner-only suspended member and the invitation history are gone.
      expect(find.text('Tom Byrne'), findsNothing);
      expect(find.byType(RetailerInvitationCard), findsNothing);
    });

    testWidgets('Retailer Manager to Retailer Owner leaves nothing behind', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.retailerManager,
      );
      expect(find.byType(RetailerStaffMemberCard), findsWidgets);

      app.retailerStaff.nextMembers = otherStaff;
      app.portal.result = resolvedResult(PortalKind.retailerOwner);
      app.auth.emitSignedIn(secondUser);
      await tester.pumpAndSettle();

      expect(currentLocation(tester), RetailerOwnerNavigation.overview);
      expect(find.text('Priya Raman'), findsNothing);
    });

    testWidgets('Retailer to Vendor leaves no Retailer data', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
      );
      await goTo(tester, RetailerOwnerNavigation.products);
      expect(find.text('Espresso Blend 1kg'), findsOneWidget);

      app.portal.result = resolvedResult(PortalKind.vendorSuperAdmin);
      app.auth.emitSignedIn(secondUser);
      await tester.pumpAndSettle();

      expect(currentLocation(tester), VendorNavigation.dashboard);
      expect(find.byType(RetailerProductCard), findsNothing);
      expect(find.text('Espresso Blend 1kg'), findsNothing);
    });

    testWidgets('Retailer to Sales Staff leaves no Retailer data', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
      );
      await goTo(tester, RetailerOwnerNavigation.shops);

      app.portal.result = resolvedResult(PortalKind.salesStaff);
      app.auth.emitSignedIn(secondUser);
      await tester.pumpAndSettle();

      expect(currentLocation(tester), SalesStaffNavigation.submit);
      expect(find.byType(RetailerShopCard), findsNothing);
    });

    testWidgets('signing out clears every tab', (WidgetTester tester) async {
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
      );
      await goTo(tester, RetailerOwnerNavigation.staff);
      expect(find.text('Priya Raman'), findsOneWidget);

      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      expect(currentLocation(tester), '/login');
      expect(find.byType(RetailerStaffMemberCard), findsNothing);
      expect(find.text('Priya Raman'), findsNothing);
    });

    testWidgets('a stale answer cannot land after a role switch', (
      WidgetTester tester,
    ) async {
      final FakeRetailerShopRepository repo = FakeRetailerShopRepository()
        ..manual = true;
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        retailerShops: repo,
      );

      // Pumped rather than settled: the read never completes, so the loading
      // skeleton shimmers indefinitely by design and `pumpAndSettle` would time
      // out waiting for an animation that is supposed to keep running.
      GoRouter.of(
        tester.element(find.byType(Navigator).first),
      ).go(RetailerOwnerNavigation.shops);
      await tester.pump();
      await tester.pump();
      expect(repo.pendingCount, 1);

      app.portal.result = resolvedResult(PortalKind.salesStaff);
      app.auth.emitSignedIn(secondUser);
      await tester.pumpAndSettle();

      // The previous Retailer's answer arrives now.
      repo.complete();
      await tester.pumpAndSettle();

      expect(currentLocation(tester), SalesStaffNavigation.submit);
      expect(find.text('Northwind Marina'), findsNothing);
    });

    testWidgets('an identical re-emitted session re-reads nothing', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
      );
      await goTo(tester, RetailerOwnerNavigation.shops);
      expect(app.retailerShops.callCount, 1);

      app.auth.emitTokenRefreshed(testUser);
      await tester.pumpAndSettle();

      expect(app.retailerShops.callCount, 1);
      expect(find.text('Northwind Marina'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('no screen leaks a backend detail', () {
    testWidgets('every problem renders only fixed copy', (
      WidgetTester tester,
    ) async {
      for (final RetailerReadProblem problem in RetailerReadProblem.values) {
        await unmountApp(tester);
        final FakeRetailerShopRepository repo = FakeRetailerShopRepository()
          ..result = RetailerShopsFailed(problem);
        await pumpAppInRole(
          tester,
          PortalKind.retailerOwner,
          retailerShops: repo,
        );
        await goTo(tester, RetailerOwnerNavigation.shops);

        final String screen = tester
            .widgetList<Text>(find.byType(Text))
            .map((Text t) => t.data ?? '')
            .join(' ');

        for (final String forbidden in <String>[
          '42501',
          'PostgrestException',
          'SQLSTATE',
          'public.',
          'auth.uid',
          'retailer_shops',
          'organization_members',
          'list_retailer_owner_portal_shops',
        ]) {
          expect(
            screen.contains(forbidden),
            isFalse,
            reason: '${problem.name} leaked "$forbidden"',
          );
        }
      }
    });

    testWidgets('no raw UUID appears on any of the three screens', (
      WidgetTester tester,
    ) async {
      final RegExp uuid = RegExp(
        r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
        r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
      );

      for (final String route in <String>[
        RetailerOwnerNavigation.shops,
        RetailerOwnerNavigation.staff,
        RetailerOwnerNavigation.products,
      ]) {
        await unmountApp(tester);
        await pumpAppInRole(tester, PortalKind.retailerOwner);
        await goTo(tester, route);

        for (final Text text in tester.widgetList<Text>(find.byType(Text))) {
          expect(
            uuid.hasMatch(text.data ?? ''),
            isFalse,
            reason: '$route rendered a UUID: ${text.data}',
          );
        }
      }
    });
  });
}
