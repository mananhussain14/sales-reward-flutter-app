import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/navigation/role_destination.dart';
import 'package:sale_reward/app/router/app_router.dart';
import 'package:sale_reward/app/shells/retailer_manager/retailer_manager_navigation.dart';
import 'package:sale_reward/app/shells/retailer_owner/retailer_owner_navigation.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_navigation.dart';
import 'package:sale_reward/app/shells/vendor/vendor_navigation.dart';
import 'package:sale_reward/core/result/read_result.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/auth/domain/entities/auth_user.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/auth/presentation/bloc/session_bloc.dart';
import 'package:sale_reward/features/roles/data/datasources/vendor_role_rpc_data_source.dart';
import 'package:sale_reward/features/roles/data/repositories/supabase_vendor_role_repository.dart';
import 'package:sale_reward/features/roles/domain/entities/vendor_role_detail.dart';
import 'package:sale_reward/features/roles/domain/entities/vendor_role_permission.dart';
import 'package:sale_reward/features/roles/domain/entities/vendor_role_summary.dart';
import 'package:sale_reward/features/roles/presentation/vendor/pages/vendor_role_detail_page.dart';
import 'package:sale_reward/features/roles/presentation/vendor/pages/vendor_roles_page.dart';
import 'package:sale_reward/features/roles/presentation/vendor/widgets/vendor_role_card.dart';
import 'package:sale_reward/features/roles/presentation/vendor/widgets/vendor_role_copy.dart';
import 'package:sale_reward/features/roles/presentation/vendor/widgets/vendor_role_permission_tile.dart';

import '../../support/fakes.dart';
import '../../support/pump_app.dart';
import '../../support/vendor_role_fakes.dart';

/// Drives the Vendor Role screens through the real application: real router,
/// real shell, real cubits, over a fake repository that never touches Supabase.

/// Navigates the live router, as a deep link or a typed URL would.
Future<void> goTo(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Navigator).first)).go(location);
  await tester.pumpAndSettle();
}

/// Where the router actually ended up.
String currentLocation(WidgetTester tester) => GoRouter.of(
  tester.element(find.byType(Navigator).first),
).routeInformationProvider.value.uri.path;

/// Scrolls [finder] into view before tapping it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Any [Semantics] whose label contains [fragment].
Finder semanticsContaining(String fragment) => find.byWidgetPredicate(
  (Widget widget) =>
      widget is Semantics &&
      (widget.properties.label?.contains(fragment) ?? false),
  description: 'Semantics whose label contains "$fragment"',
);

/// A second signed-in person, so a user switch is a real change of identity.
const AuthUser secondUser = AuthUser(id: 'user-2', email: 'pat@example.com');

void main() {
  /// Signs in as a Vendor Super Admin and opens the Roles catalogue.
  Future<PumpedApp> onCatalogue(
    WidgetTester tester, {
    FakeVendorRoleRepository? roles,
    Size surface = phoneSurface,
  }) async {
    final PumpedApp app = await pumpAppInRole(
      tester,
      PortalKind.vendorSuperAdmin,
      surface: surface,
      vendorRoles: roles,
    );
    await goTo(tester, VendorNavigation.roles);
    return app;
  }

  group('route isolation', () {
    test('the guard sends every other role away from both routes', () {
      for (final PortalKind kind in <PortalKind>[
        PortalKind.retailerOwner,
        PortalKind.retailerManager,
        PortalKind.salesStaff,
      ]) {
        final SessionState session = SessionActive(contextFor(kind));
        final String home = sessionHome(session);

        expect(redirectFor(session, VendorNavigation.roles), home);
        expect(
          redirectFor(
            session,
            VendorNavigation.roleDetailPath(superAdminRoleUuid),
          ),
          home,
        );
      }
    });

    test('a Vendor Super Admin is allowed into both', () {
      final SessionState session = SessionActive(
        contextFor(PortalKind.vendorSuperAdmin),
      );

      expect(redirectFor(session, VendorNavigation.roles), isNull);
      expect(
        redirectFor(
          session,
          VendorNavigation.roleDetailPath(superAdminRoleUuid),
        ),
        isNull,
      );
    });

    test('a signed-out caller is sent to login, not to the catalogue', () {
      expect(
        redirectFor(const SessionUnauthenticated(), VendorNavigation.roles),
        '/login',
      );
    });

    test('the detail route is the role id under the Roles path', () {
      expect(
        VendorNavigation.roleDetailPath(superAdminRoleUuid),
        '/vendor/roles/$superAdminRoleUuid',
      );
      expect(
        VendorNavigation.roleDetailPath(
          superAdminRoleUuid,
        ).startsWith(VendorNavigation.roles),
        isTrue,
      );
    });

    test('the route selector is never a role code or a name', () {
      // roles.code is UNIQUE and would address a role just as precisely, which
      // is exactly why it is refused: the codes are the literals the RLS
      // policies match on.
      final String path = VendorNavigation.roleDetailPath(superAdminRoleUuid);

      expect(path.contains('VENDOR_SUPER_ADMIN'), isFalse);
      expect(path.contains('Vendor%20Super%20Admin'), isFalse);
      expect(path.endsWith(superAdminRoleUuid), isTrue);
    });

    test('Roles stays the selected destination for list and detail', () {
      // Longest-prefix wins, so an open role does not fall back to Dashboard.
      final RoleNavigation model = VendorNavigation.model;
      final int rolesIndex = model.destinations.indexWhere(
        (RoleDestination d) => d.path == VendorNavigation.roles,
      );

      expect(model.indexForLocation(VendorNavigation.roles), rolesIndex);
      expect(
        model.indexForLocation(
          VendorNavigation.roleDetailPath(superAdminRoleUuid),
        ),
        rolesIndex,
      );
    });

    testWidgets('a Retailer Owner cannot reach the Vendor Role routes', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerOwner);

      await goTo(tester, VendorNavigation.roles);
      expect(find.byType(VendorRolesPage), findsNothing);

      await goTo(tester, VendorNavigation.roleDetailPath(superAdminRoleUuid));
      expect(find.byType(VendorRoleDetailPage), findsNothing);
      expect(currentLocation(tester), RetailerOwnerNavigation.overview);
    });

    testWidgets('a Retailer Manager cannot reach them either', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerManager);

      await goTo(tester, VendorNavigation.roleDetailPath(superAdminRoleUuid));

      expect(find.byType(VendorRoleDetailPage), findsNothing);
      expect(currentLocation(tester), RetailerManagerNavigation.staff);
    });

    testWidgets('Sales Staff cannot reach them either', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);

      await goTo(tester, VendorNavigation.roles);

      expect(find.byType(VendorRolesPage), findsNothing);
      expect(currentLocation(tester), SalesStaffNavigation.home);
    });

    testWidgets('no other role even reads the Vendor Role RPCs', (
      WidgetTester tester,
    ) async {
      final FakeVendorRoleRepository repository = FakeVendorRoleRepository();

      await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        vendorRoles: repository,
      );
      await goTo(tester, VendorNavigation.roles);

      // The shell that owns the cubits is never built for this role.
      expect(repository.rolesCallCount, 0);
      expect(repository.detailCallCount, 0);
      expect(repository.permissionsCallCount, 0);
    });

    testWidgets('a role name in the data never authorizes anything', (
      WidgetTester tester,
    ) async {
      // The catalogue contains a role literally called "Vendor Super Admin".
      // Reaching this screen is decided by the session's portal kind and, on
      // every call, by SQL — never by a string the backend sent for display.
      final FakeVendorRoleRepository repository = FakeVendorRoleRepository();

      await pumpAppInRole(
        tester,
        PortalKind.salesStaff,
        vendorRoles: repository,
      );
      await goTo(tester, VendorNavigation.roles);

      expect(find.text('Vendor Super Admin'), findsNothing);
      expect(repository.rolesCallCount, 0);
    });
  });

  group('the catalogue', () {
    testWidgets('a Vendor Super Admin reaches it and sees every definition', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCatalogue(tester);

      expect(find.byType(VendorRolesPage), findsOneWidget);
      expect(find.byType(VendorRoleCard), findsNWidgets(4));
      expect(find.text('Vendor Super Admin'), findsOneWidget);
      expect(find.text('Claim Reviewer'), findsOneWidget);
      // One read for the whole screen, and no detail or permission read.
      expect(app.vendorRoles.rolesCallCount, 1);
      expect(app.vendorRoles.detailCallCount, 0);
      expect(app.vendorRoles.permissionsCallCount, 0);
    });

    testWidgets('nothing is read until the catalogue is actually opened', (
      WidgetTester tester,
    ) async {
      final FakeVendorRoleRepository repository = FakeVendorRoleRepository();
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.vendorSuperAdmin,
        vendorRoles: repository,
      );

      expect(repository.rolesCallCount, 0);

      await goTo(tester, VendorNavigation.users);
      expect(repository.rolesCallCount, 0);
      expect(app.vendorUsers.usersCallCount, 1);

      await goTo(tester, VendorNavigation.roles);
      expect(repository.rolesCallCount, 1);
    });

    testWidgets('shows a loading skeleton before the first answer', (
      WidgetTester tester,
    ) async {
      final FakeVendorRoleRepository repository = FakeVendorRoleRepository()
        ..manualRoles = true;

      await pumpAppInRole(
        tester,
        PortalKind.vendorSuperAdmin,
        vendorRoles: repository,
      );
      GoRouter.of(
        tester.element(find.byType(Navigator).first),
      ).go(VendorNavigation.roles);
      // Two frames: one for the router to swap the route, one for the page to
      // build. Deliberately not pumpAndSettle — the skeleton shimmers forever.
      await tester.pump();
      await tester.pump();

      expect(find.byType(SrLoadingView), findsOneWidget);
      expect(find.byType(VendorRoleCard), findsNothing);

      repository.completeRoles();
      await tester.pumpAndSettle();

      expect(find.byType(SrLoadingView), findsNothing);
      expect(find.byType(VendorRoleCard), findsNWidgets(4));
    });

    testWidgets('every row is visibly actionable', (WidgetTester tester) async {
      await onCatalogue(tester);

      expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(4));
      expect(find.text(VendorRoleCopy.openDetails), findsNWidgets(4));
      for (final VendorRoleCard card in tester.widgetList<VendorRoleCard>(
        find.byType(VendorRoleCard),
      )) {
        expect(card.onOpen, isNotNull);
      }
    });

    testWidgets('the shared-catalogue explanation is on screen', (
      WidgetTester tester,
    ) async {
      // A Vendor who finds "Retailer Owner" in their own Roles screen must be
      // able to read why.
      await onCatalogue(tester);

      expect(find.text(VendorRoleCopy.listDescription), findsOneWidget);
      expect(find.text(VendorRoleCopy.sharedCatalogueNote), findsOneWidget);
    });

    testWidgets('Retailer role definitions are listed, not hidden', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);

      expect(find.text('Retailer Owner'), findsOneWidget);
    });

    testWidgets('no role is labelled Vendor, Retailer, system or custom', (
      WidgetTester tester,
    ) async {
      // There is no scope, kind, is_system or is_custom column anywhere, so any
      // such badge could only have been invented from the role name.
      //
      // Scoped to the cards: the page's shared-catalogue note legitimately says
      // "Retailer roles appear here too", which is an *explanation* of the
      // global catalogue rather than a label applied to a row.
      await onCatalogue(tester);

      for (final String forbidden in <String>[
        'System role',
        'Custom role',
        'Built-in',
        'Vendor role',
        'Retailer role',
        'Scope',
      ]) {
        expect(
          find.descendant(
            of: find.byType(VendorRoleCard),
            matching: find.textContaining(forbidden),
          ),
          findsNothing,
          reason: 'a role card invents "$forbidden"',
        );
      }
    });

    testWidgets('no role code or permission code is displayed', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);

      for (final String code in <String>[
        'VENDOR_SUPER_ADMIN',
        'RETAILER_OWNER',
        'CLAIM_REVIEWER',
        'RBAC_READ',
        'ORGANIZATION_MEMBERS_READ',
      ]) {
        expect(find.textContaining(code), findsNothing);
      }
    });

    testWidgets('both statuses render with a word and a glyph', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);

      expect(find.text('Status: Active'), findsNWidgets(3));
      expect(find.text('Status: Inactive'), findsOneWidget);
      expect(find.byIcon(Icons.block_rounded), findsWidgets);
    });

    testWidgets('permission counts are worded as mapped, not effective', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);

      expect(find.text('3 permissions mapped'), findsOneWidget);
      expect(find.text('2 permissions mapped'), findsNWidgets(2));
      expect(find.text('No permissions mapped'), findsOneWidget);
      // Never a claim about the reader.
      expect(find.textContaining('You can'), findsNothing);
      expect(find.textContaining('Your permissions'), findsNothing);
    });

    testWidgets('member counts say they are this Vendor\'s', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);

      expect(find.text('2 members in your Vendor'), findsOneWidget);
      expect(find.text('1 member in your Vendor'), findsOneWidget);
      expect(find.text('No members in your Vendor'), findsNWidgets(2));
    });

    testWidgets('a null description renders a phrase, never a fabrication', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);

      expect(find.text(VendorRoleCopy.noDescription), findsOneWidget);
    });

    testWidgets('the creation date is shown', (WidgetTester tester) async {
      await onCatalogue(tester);

      expect(find.text('Created 5 Jan 2026'), findsOneWidget);
    });

    testWidgets('the card carries a spoken summary and an open hint', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);

      expect(semanticsContaining('Vendor Super Admin'), findsWidgets);
      expect(semanticsContaining('Role status: Active'), findsWidgets);
      expect(semanticsContaining('3 permissions mapped'), findsWidgets);
      expect(semanticsContaining('2 members in your Vendor'), findsWidgets);

      final Semantics semantics = tester.widget<Semantics>(
        semanticsContaining('Role status: Inactive').first,
      );
      expect(semantics.properties.label, isNot(contains(legacyRoleUuid)));
    });

    testWidgets('the summary figures come from the returned rows', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);

      expect(find.text(VendorRoleCopy.totalLabel), findsOneWidget);
      expect(find.text(VendorRoleCopy.activeLabel), findsOneWidget);
      expect(find.text(VendorRoleCopy.inactiveLabel), findsOneWidget);
      expect(find.text(VendorRoleCopy.mappingsLabel), findsOneWidget);
      expect(find.text('4'), findsOneWidget); // total
      expect(find.text('7'), findsOneWidget); // mappings
    });

    testWidgets('an all-active catalogue shows no inactive card', (
      WidgetTester tester,
    ) async {
      final FakeVendorRoleRepository repository = FakeVendorRoleRepository()
        ..rolesResult = ReadSuccess<List<VendorRoleSummary>>(
          <VendorRoleSummary>[superAdminSummary, claimReviewerSummary],
        );

      await onCatalogue(tester, roles: repository);

      expect(find.text(VendorRoleCopy.inactiveLabel), findsNothing);
    });

    testWidgets('an empty response is handled safely', (
      WidgetTester tester,
    ) async {
      // Not reachable while authorized, but a defensive floor all the same.
      final FakeVendorRoleRepository repository = FakeVendorRoleRepository()
        ..rolesResult = const ReadSuccess<List<VendorRoleSummary>>(
          <VendorRoleSummary>[],
        );

      await onCatalogue(tester, roles: repository);

      expect(find.text(VendorRoleCopy.emptyTitle), findsOneWidget);
      expect(find.byType(VendorRoleCard), findsNothing);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('a failed first read offers a retry that works', (
      WidgetTester tester,
    ) async {
      final FakeVendorRoleRepository repository = FakeVendorRoleRepository()
        ..rolesResult = unavailableRoleRead<List<VendorRoleSummary>>();

      await onCatalogue(tester, roles: repository);

      expect(find.byType(SrFailureView), findsOneWidget);
      expect(find.text('Could not load this'), findsOneWidget);

      repository.rolesResult = ReadSuccess<List<VendorRoleSummary>>(
        catalogueSummaries,
      );
      await tapVisible(tester, find.text('Try again'));

      expect(find.byType(VendorRoleCard), findsNWidgets(4));
    });

    testWidgets('a denial never offers a retry', (WidgetTester tester) async {
      final FakeVendorRoleRepository repository = FakeVendorRoleRepository()
        ..rolesResult = deniedRoleRead<List<VendorRoleSummary>>();

      await onCatalogue(tester, roles: repository);

      expect(find.text('Not available to this account'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('refreshing re-reads without blanking the rows', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCatalogue(tester);

      await tester.tap(find.text(VendorRoleCopy.refresh));
      await tester.pump();

      expect(find.byType(VendorRoleCard), findsNWidgets(4));

      await tester.pumpAndSettle();
      expect(app.vendorRoles.rolesCallCount, 2);
    });

    testWidgets('a failed refresh keeps the rows and warns', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCatalogue(tester);
      app.vendorRoles.rolesResult =
          unavailableRoleRead<List<VendorRoleSummary>>();

      await tapVisible(tester, find.text(VendorRoleCopy.refresh));

      expect(find.byType(VendorRoleCard), findsNWidgets(4));
      expect(find.text(VendorRoleCopy.staleListTitle), findsOneWidget);
    });

    testWidgets('no write affordance exists anywhere', (
      WidgetTester tester,
    ) async {
      // There is no role write backend at all — on web or mobile — so an
      // affordance, even a disabled one, would advertise a feature that does not
      // exist.
      await onCatalogue(tester);

      for (final String forbidden in <String>[
        'Create role',
        'New role',
        'Add role',
        'Edit role',
        'Delete role',
        'Duplicate',
        'Activate',
        'Deactivate',
        'Assign permission',
        'Remove permission',
        'Assign role',
      ]) {
        expect(
          find.textContaining(forbidden),
          findsNothing,
          reason: 'the catalogue offers "$forbidden"',
        );
      }
    });
  });

  group('search and filtering', () {
    testWidgets('a local search narrows the loaded rows only', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCatalogue(tester);

      await tester.enterText(find.byType(TextField).first, 'legacy');
      await tester.pumpAndSettle();

      expect(find.text('Legacy Auditor'), findsOneWidget);
      expect(find.text('Vendor Super Admin'), findsNothing);
      expect(find.text('Showing 1 of 4'), findsOneWidget);
      // Nothing was sent anywhere.
      expect(app.vendorRoles.rolesCallCount, 1);
    });

    testWidgets('a search matching nothing offers a way back', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);

      await tester.enterText(find.byType(TextField).first, 'zzzz');
      await tester.pumpAndSettle();

      expect(find.text(VendorRoleCopy.noMatchesTitle), findsOneWidget);

      await tapVisible(tester, find.text(VendorRoleCopy.clearFilters).first);

      expect(find.byType(VendorRoleCard), findsNWidgets(4));
    });

    testWidgets('the status filter row is offered and works', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester, surface: tabletSurface);

      expect(find.text(VendorRoleCopy.statusFilterLabel), findsOneWidget);
      expect(find.widgetWithText(SrButton, 'All'), findsOneWidget);
      expect(find.widgetWithText(SrButton, 'Active'), findsOneWidget);
      expect(find.widgetWithText(SrButton, 'Inactive'), findsOneWidget);
      // Nothing has an unrecognised status in the fixture, so no chip offers it.
      expect(find.widgetWithText(SrButton, 'Unknown'), findsNothing);

      await tapVisible(tester, find.widgetWithText(SrButton, 'Inactive'));

      expect(find.text('Legacy Auditor'), findsOneWidget);
      expect(find.text('Vendor Super Admin'), findsNothing);
    });

    testWidgets('filter chips carry their subject in the semantics', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester, surface: tabletSurface);

      expect(semanticsContaining('Role status: Active'), findsWidgets);
      expect(
        semanticsContaining('${VendorRoleCopy.statusFilterLabel}: All'),
        findsWidgets,
      );
    });
  });

  group('opening a role', () {
    testWidgets('tapping a row opens that role, in the right order', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCatalogue(tester);

      await tapVisible(tester, find.text('Vendor Super Admin'));

      expect(find.byType(VendorRoleDetailPage), findsOneWidget);
      expect(app.vendorRoles.requestedDetailIds, <String>[superAdminRoleUuid]);
      expect(app.vendorRoles.requestedPermissionIds, <String>[
        superAdminRoleUuid,
      ]);
      expect(app.vendorRoles.callLog, <String>[
        'roles',
        'detail',
        'permissions',
      ]);
      expect(
        currentLocation(tester),
        VendorNavigation.roleDetailPath(superAdminRoleUuid),
      );
    });

    testWidgets('the detail renders every field the contract returns', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);
      await tapVisible(tester, find.text('Vendor Super Admin'));

      expect(find.text('Vendor Super Admin'), findsOneWidget);
      expect(find.text('Status: Active'), findsOneWidget);
      expect(
        find.text('Full administrative control of a Vendor organization.'),
        findsOneWidget,
      );
      expect(find.text('3 permissions mapped'), findsNWidgets(2));
      expect(find.text('2 members in your Vendor'), findsOneWidget);
      expect(find.text('5 Jan 2026'), findsOneWidget);
    });

    testWidgets('the permission rows render name over description', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);
      await tapVisible(tester, find.text('Vendor Super Admin'));

      expect(find.byType(VendorRolePermissionTile), findsNWidgets(3));
      expect(find.text('Manage retailers'), findsOneWidget);
      expect(
        find.text('Create and maintain Retailer relationships.'),
        findsOneWidget,
      );
      // A permission with no description says so rather than showing a blank.
      expect(find.text(VendorRoleCopy.noPermissionDescription), findsOneWidget);
    });

    testWidgets('permission order is the backend\'s, never re-sorted', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);
      await tapVisible(tester, find.text('Vendor Super Admin'));

      final List<String> rendered = tester
          .widgetList<VendorRolePermissionTile>(
            find.byType(VendorRolePermissionTile),
          )
          .map((VendorRolePermissionTile t) => t.permission.name)
          .toList();

      expect(rendered, <String>[
        'Manage retailers',
        'Read organization members',
        'Read roles',
      ]);
    });

    testWidgets('an active role shows no effectiveness notice', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);
      await tapVisible(tester, find.text('Vendor Super Admin'));

      expect(find.text(VendorRoleCopy.inactiveNoticeTitle), findsNothing);
      expect(find.text(VendorRoleCopy.inactiveNoticeBody), findsNothing);
    });

    testWidgets('permissions are described as mapped to the role', (
      WidgetTester tester,
    ) async {
      // Never "your permissions", and never "effective permissions for the
      // current user".
      await onCatalogue(tester);
      await tapVisible(tester, find.text('Vendor Super Admin'));

      expect(find.text(VendorRoleCopy.permissionsDescription), findsOneWidget);
      expect(find.textContaining('you can'), findsNothing);
      expect(find.textContaining('Effective permissions'), findsNothing);
    });

    testWidgets('a permission carries a spoken name-and-description pair', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);
      await tapVisible(tester, find.text('Vendor Super Admin'));

      expect(semanticsContaining('Permission: Manage retailers'), findsWidgets);
    });

    testWidgets('a role with no permissions says so', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCatalogue(tester);
      await tapVisible(tester, find.text('Claim Reviewer'));

      expect(find.text(VendorRoleCopy.permissionsEmptyTitle), findsOneWidget);
      expect(find.byType(VendorRolePermissionTile), findsNothing);
      // The companion WAS called — the empty list is a real answer, not the
      // ambiguous one an unknown id would have produced.
      expect(app.vendorRoles.permissionsCallCount, 1);
    });

    testWidgets('no permission code, module or per-permission status shows', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);
      await tapVisible(tester, find.text('Vendor Super Admin'));

      for (final String forbidden in <String>[
        'RBAC',
        'ORGANIZATION_MEMBERS',
        'Module',
        'Permission status',
        'Permission code',
      ]) {
        expect(
          find.textContaining(forbidden),
          findsNothing,
          reason: 'the detail exposes "$forbidden"',
        );
      }
    });

    testWidgets('no identifier is put on screen', (WidgetTester tester) async {
      await onCatalogue(tester);
      await tapVisible(tester, find.text('Vendor Super Admin'));

      expect(find.textContaining(superAdminRoleUuid), findsNothing);
      expect(find.textContaining('Organization ID'), findsNothing);
      expect(find.textContaining('Role ID'), findsNothing);
    });

    testWidgets('the detail facts are spoken as label-and-value pairs', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);
      await tapVisible(tester, find.text('Vendor Super Admin'));

      expect(
        semanticsContaining('${VendorRoleCopy.statusLabel}: Active'),
        findsWidgets,
      );
      expect(
        semanticsContaining(
          '${VendorRoleCopy.assignedMembersLabel}: 2 members in your Vendor',
        ),
        findsWidgets,
      );
    });

    testWidgets('going back keeps the catalogue already loaded', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCatalogue(tester);

      await tapVisible(tester, find.text('Vendor Super Admin'));
      await tapVisible(tester, find.text(VendorRoleCopy.backToList));

      expect(find.byType(VendorRolesPage), findsOneWidget);
      expect(find.byType(VendorRoleCard), findsNWidgets(4));
      // No skeleton, and no second catalogue read.
      expect(app.vendorRoles.rolesCallCount, 1);
    });

    testWidgets('a browser-style back pop also returns to the loaded list', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCatalogue(tester);
      await tapVisible(tester, find.text('Vendor Super Admin'));

      // What the hardware/browser back button drives.
      final NavigatorState navigator = tester.state<NavigatorState>(
        find.byType(Navigator).last,
      );
      navigator.pop();
      await tester.pumpAndSettle();

      expect(find.byType(VendorRolesPage), findsOneWidget);
      expect(find.byType(VendorRoleCard), findsNWidgets(4));
      expect(app.vendorRoles.rolesCallCount, 1);
    });
  });

  group('an inactive role', () {
    testWidgets('shows the effectiveness notice prominently', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);
      await tapVisible(tester, find.text('Legacy Auditor'));

      expect(find.text(VendorRoleCopy.inactiveNoticeTitle), findsOneWidget);
      expect(find.text(VendorRoleCopy.inactiveNoticeBody), findsOneWidget);
      // Not colour alone: a glyph and a full sentence carry it too.
      expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
      expect(
        semanticsContaining(VendorRoleCopy.inactiveNoticeSemantics),
        findsWidgets,
      );
    });

    testWidgets('still displays every mapped permission', (
      WidgetTester tester,
    ) async {
      // Filtering them out would make a retired role look permission-less and
      // hide the very state the screen exists to explain.
      await onCatalogue(tester);
      await tapVisible(tester, find.text('Legacy Auditor'));

      expect(find.byType(VendorRolePermissionTile), findsNWidgets(2));
      expect(find.text('Read audit log'), findsOneWidget);
      expect(find.text('Read reports'), findsOneWidget);
    });

    testWidgets('leaves the permission count unchanged', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);
      await tapVisible(tester, find.text('Legacy Auditor'));

      expect(find.text('2 permissions mapped'), findsNWidgets(2));
    });

    testWidgets('keeps the role status visible beside the permissions', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);
      await tapVisible(tester, find.text('Legacy Auditor'));

      expect(find.text('Status: Inactive'), findsOneWidget);
      expect(find.text('Inactive'), findsOneWidget); // the labelled fact
      expect(find.byType(VendorRolePermissionTile), findsNWidgets(2));
    });

    testWidgets('never implies the role currently grants access', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);
      await tapVisible(tester, find.text('Legacy Auditor'));

      for (final String forbidden in <String>[
        'currently grants',
        'These permissions apply',
        'Effective',
        'You have',
      ]) {
        expect(find.textContaining(forbidden), findsNothing);
      }
    });

    testWidgets('no permission carries its own active or inactive badge', (
      WidgetTester tester,
    ) async {
      // There is no permission status column anywhere in the schema, so such a
      // badge could only be invented.
      await onCatalogue(tester);
      await tapVisible(tester, find.text('Legacy Auditor'));

      expect(find.text('Status: Active'), findsNothing);
      // Exactly one status pill on the page: the role's.
      expect(find.byType(SrBadge), findsOneWidget);
    });
  });

  group('a role this caller cannot address', () {
    testWidgets('a manually typed unknown id shows one safe state', (
      WidgetTester tester,
    ) async {
      final FakeVendorRoleRepository repository = FakeVendorRoleRepository()
        ..detailResult = const ReadSuccess<VendorRoleDetail?>(null);

      await onCatalogue(tester, roles: repository);
      await goTo(tester, VendorNavigation.roleDetailPath(unknownRoleUuid));

      expect(find.text(VendorRoleCopy.detailNotFoundTitle), findsOneWidget);
      // Says nothing about existence or ownership — and there is no other Vendor
      // for a global role to belong to.
      expect(find.textContaining('another Vendor'), findsNothing);
      expect(find.textContaining('exists'), findsNothing);
      expect(find.textContaining('belongs to'), findsNothing);
      // Not an outage: no retry.
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('a malformed id in the URL reaches the same state', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester);
      await goTo(tester, '${VendorNavigation.roles}/not-a-uuid');

      expect(find.text(VendorRoleCopy.detailNotFoundTitle), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('a malformed id makes ZERO detail and permission RPC calls', (
      WidgetTester tester,
    ) async {
      // Driven through the **real** repository over a counting data source, so
      // the id-shape guard is genuinely in the path rather than stubbed out.
      //
      // Both companions take a PostgreSQL `uuid`, so a malformed selector that
      // reached either would come back as a `22P02` cast error — an operational
      // failure wearing the wrong clothes, with a retry that could never
      // succeed.
      int detailCalls = 0;
      int permissionCalls = 0;
      int listCalls = 0;

      final SupabaseVendorRoleRepository real = SupabaseVendorRoleRepository(
        rpc: VendorRoleRpcDataSource(
          roles: () async {
            listCalls++;
            return roleRows();
          },
          detail: (String roleId) async {
            detailCalls++;
            return <Map<String, Object?>>[roleRow()];
          },
          permissions: (String roleId) async {
            permissionCalls++;
            return <Map<String, Object?>>[permissionRow()];
          },
        ),
      );

      await pumpAppInRole(
        tester,
        PortalKind.vendorSuperAdmin,
        vendorRoleRepository: real,
      );
      await goTo(tester, VendorNavigation.roles);
      expect(listCalls, 1);

      await goTo(tester, '${VendorNavigation.roles}/not-a-uuid');

      // The whole point.
      expect(detailCalls, 0);
      expect(permissionCalls, 0);
      expect(find.text(VendorRoleCopy.detailNotFoundTitle), findsOneWidget);
      // And nothing raw leaked in place of the safe wording.
      expect(find.textContaining('22P02'), findsNothing);
      expect(find.textContaining('uuid'), findsNothing);
      expect(find.textContaining('PostgrestException'), findsNothing);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('a valid unknown id calls detail once and permissions never', (
      WidgetTester tester,
    ) async {
      int detailCalls = 0;
      int permissionCalls = 0;

      final SupabaseVendorRoleRepository real = SupabaseVendorRoleRepository(
        rpc: VendorRoleRpcDataSource(
          roles: () async => roleRows(),
          detail: (String roleId) async {
            detailCalls++;
            return const <Object?>[]; // zero rows
          },
          permissions: (String roleId) async {
            permissionCalls++;
            return const <Object?>[];
          },
        ),
      );

      await pumpAppInRole(
        tester,
        PortalKind.vendorSuperAdmin,
        vendorRoleRepository: real,
      );
      await goTo(tester, VendorNavigation.roles);
      await goTo(tester, VendorNavigation.roleDetailPath(unknownRoleUuid));

      expect(detailCalls, 1);
      // The detail read is the authoritative existence check, so the companion
      // is never asked.
      expect(permissionCalls, 0);
      expect(find.text(VendorRoleCopy.detailNotFoundTitle), findsOneWidget);
    });

    testWidgets('the safe state offers a way back to the catalogue', (
      WidgetTester tester,
    ) async {
      final FakeVendorRoleRepository repository = FakeVendorRoleRepository()
        ..detailResult = const ReadSuccess<VendorRoleDetail?>(null);

      await onCatalogue(tester, roles: repository);
      await goTo(tester, VendorNavigation.roleDetailPath(unknownRoleUuid));

      await tapVisible(tester, find.text(VendorRoleCopy.backToList).last);

      expect(find.byType(VendorRolesPage), findsOneWidget);
    });
  });

  group('the permission section degrades on its own', () {
    testWidgets('a permission failure keeps the role detail on screen', (
      WidgetTester tester,
    ) async {
      final FakeVendorRoleRepository repository = FakeVendorRoleRepository()
        ..permissionsResult = unavailableRoleRead<List<VendorRolePermission>>();

      await onCatalogue(tester, roles: repository);
      await tapVisible(tester, find.text('Vendor Super Admin'));

      expect(
        find.text(VendorRoleCopy.permissionsUnavailableTitle),
        findsOneWidget,
      );
      // The role's own facts came from a call that succeeded.
      expect(find.text('Status: Active'), findsOneWidget);
      expect(find.text('2 members in your Vendor'), findsOneWidget);
    });

    testWidgets('its retry re-reads only the permissions', (
      WidgetTester tester,
    ) async {
      final FakeVendorRoleRepository repository = FakeVendorRoleRepository()
        ..permissionsResult = unavailableRoleRead<List<VendorRolePermission>>();

      await onCatalogue(tester, roles: repository);
      await tapVisible(tester, find.text('Vendor Super Admin'));
      expect(repository.detailCallCount, 1);

      repository.permissionsResult = null;
      await tapVisible(tester, find.text(VendorRoleCopy.retryPermissions));

      expect(repository.detailCallCount, 1);
      expect(repository.permissionsCallCount, 2);
      expect(find.byType(VendorRolePermissionTile), findsNWidgets(3));
    });

    testWidgets('a role status stays visible through a permission failure', (
      WidgetTester tester,
    ) async {
      final FakeVendorRoleRepository repository = FakeVendorRoleRepository()
        ..permissionsResult = unavailableRoleRead<List<VendorRolePermission>>();

      await onCatalogue(tester, roles: repository);
      await tapVisible(tester, find.text('Legacy Auditor'));

      expect(find.text('Status: Inactive'), findsOneWidget);
      expect(find.text(VendorRoleCopy.inactiveNoticeTitle), findsOneWidget);
    });

    testWidgets('a count mismatch is surfaced without dropping rows', (
      WidgetTester tester,
    ) async {
      final FakeVendorRoleRepository repository = FakeVendorRoleRepository()
        ..permissionsResult = ReadSuccess<List<VendorRolePermission>>(
          <VendorRolePermission>[superAdminPermissions.first],
        );

      await onCatalogue(tester, roles: repository);
      await tapVisible(tester, find.text('Vendor Super Admin'));

      expect(find.text(VendorRoleCopy.countMismatchTitle), findsOneWidget);
      // Everything returned is still rendered, and the count is unchanged.
      expect(find.byType(VendorRolePermissionTile), findsOneWidget);
      expect(find.text('3 permissions mapped'), findsNWidgets(2));
    });
  });

  group('session isolation', () {
    testWidgets('signing out clears the catalogue', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCatalogue(tester);
      expect(find.text('Vendor Super Admin'), findsOneWidget);

      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      expect(find.byType(VendorRolesPage), findsNothing);
      expect(find.text('Vendor Super Admin'), findsNothing);
      expect(find.text('2 members in your Vendor'), findsNothing);
    });

    testWidgets('an open role is cleared on sign-out too', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCatalogue(tester);
      await tapVisible(tester, find.text('Vendor Super Admin'));
      expect(find.text('Manage retailers'), findsOneWidget);

      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      expect(find.byType(VendorRoleDetailPage), findsNothing);
      expect(find.text('Manage retailers'), findsNothing);
    });

    testWidgets('a new Vendor never sees the previous one\'s member counts', (
      WidgetTester tester,
    ) async {
      final FakeVendorRoleRepository repository = FakeVendorRoleRepository();
      final PumpedApp app = await onCatalogue(tester, roles: repository);
      expect(find.text('2 members in your Vendor'), findsOneWidget);

      // The same global definitions, this Vendor's own counts.
      repository.rolesResult =
          ReadSuccess<List<VendorRoleSummary>>(<VendorRoleSummary>[
            VendorRoleSummary(
              roleId: superAdminRoleUuid,
              roleName: 'Vendor Super Admin',
              description: superAdminSummary.description,
              status: superAdminSummary.status,
              createdAt: superAdminCreatedAt,
              permissionCount: 3,
              assignedMemberCount: 9,
            ),
          ]);
      app.auth.emitSignedIn(secondUser);
      await tester.pumpAndSettle();

      expect(find.text('2 members in your Vendor'), findsNothing);
      expect(find.text('9 members in your Vendor'), findsOneWidget);
      expect(repository.rolesCallCount, 2);
    });

    testWidgets('a search term does not survive a session change', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onCatalogue(tester);
      await tester.enterText(find.byType(TextField).first, 'legacy');
      await tester.pumpAndSettle();
      expect(find.text('Showing 1 of 4'), findsOneWidget);

      app.auth.emitSignedIn(secondUser);
      await tester.pumpAndSettle();

      expect(find.text('Showing 1 of 4'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
    });

    testWidgets('the Retailer and User directories clear by the same switch', (
      WidgetTester tester,
    ) async {
      // The Role milestone must not have displaced either earlier half.
      final PumpedApp app = await onCatalogue(tester);
      await goTo(tester, VendorNavigation.retailers);
      expect(find.text('Northwind Retail'), findsOneWidget);

      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      expect(find.text('Northwind Retail'), findsNothing);
    });
  });

  group('responsive and themed', () {
    for (final (String name, Size surface) in <(String, Size)>[
      ('a small phone', smallPhoneSurface),
      ('a phone', phoneSurface),
      ('a tablet', tabletSurface),
      ('a desktop browser', desktopSurface),
    ]) {
      testWidgets('the catalogue lays out on $name without overflowing', (
        WidgetTester tester,
      ) async {
        await onCatalogue(tester, surface: surface);

        expect(find.byType(VendorRoleCard), findsNWidgets(4));
        expect(tester.takeException(), isNull);
      });

      testWidgets('a role detail lays out on $name without overflowing', (
        WidgetTester tester,
      ) async {
        await onCatalogue(tester, surface: surface);
        await tapVisible(tester, find.text('Vendor Super Admin'));

        expect(find.byType(VendorRoleDetailPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('long names and descriptions do not overflow a small phone', (
      WidgetTester tester,
    ) async {
      final FakeVendorRoleRepository repository = FakeVendorRoleRepository()
        ..rolesResult =
            ReadSuccess<List<VendorRoleSummary>>(<VendorRoleSummary>[
              VendorRoleSummary(
                roleId: superAdminRoleUuid,
                roleName:
                    'Vendor Super Administrator With An Extremely Long Title',
                description:
                    'A deliberately long description that runs well past the '
                    'width of a small phone so the card has to wrap it rather '
                    'than push anything off the side of the screen.',
                status: superAdminSummary.status,
                createdAt: superAdminCreatedAt,
                permissionCount: 128,
                assignedMemberCount: 4096,
              ),
            ]);

      await onCatalogue(tester, roles: repository, surface: smallPhoneSurface);

      expect(find.byType(VendorRoleCard), findsOneWidget);
      expect(find.text('128 permissions mapped'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long permission name and description wrap on a phone', (
      WidgetTester tester,
    ) async {
      final FakeVendorRoleRepository repository = FakeVendorRoleRepository()
        ..permissionsResult = const ReadSuccess<List<VendorRolePermission>>(
          <VendorRolePermission>[
            VendorRolePermission(
              name:
                  'Read every organization member record across the whole '
                  'platform directory',
              description:
                  'A description long enough to require several lines on a '
                  'narrow screen without ever scrolling sideways.',
            ),
          ],
        );

      await onCatalogue(tester, roles: repository, surface: smallPhoneSurface);
      await tapVisible(tester, find.text('Vendor Super Admin'));

      expect(find.byType(VendorRolePermissionTile), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the catalogue survives large text scaling', (
      WidgetTester tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await onCatalogue(tester, surface: phoneSurface);

      expect(find.byType(VendorRoleCard), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide screens use more than one column', (
      WidgetTester tester,
    ) async {
      await onCatalogue(tester, surface: desktopSurface);

      final List<Offset> positions = tester
          .widgetList<VendorRoleCard>(find.byType(VendorRoleCard))
          .map((VendorRoleCard card) => tester.getTopLeft(find.byWidget(card)))
          .toList();

      expect(positions[0].dy, positions[1].dy);
      expect(positions[0].dx, lessThan(positions[1].dx));
    });

    testWidgets('a phone stacks the cards', (WidgetTester tester) async {
      await onCatalogue(tester, surface: phoneSurface);

      final List<Offset> positions = tester
          .widgetList<VendorRoleCard>(find.byType(VendorRoleCard))
          .map((VendorRoleCard card) => tester.getTopLeft(find.byWidget(card)))
          .toList();

      expect(positions[0].dx, positions[1].dx);
      expect(positions[0].dy, lessThan(positions[1].dy));
    });

    for (final ThemeMode mode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
      testWidgets('the catalogue renders in $mode', (
        WidgetTester tester,
      ) async {
        await pumpApp(
          tester,
          initialUser: testUser,
          portalResult: resolvedResult(PortalKind.vendorSuperAdmin),
          themeMode: mode,
        );
        await goTo(tester, VendorNavigation.roles);

        expect(find.byType(VendorRoleCard), findsNWidgets(4));
        expect(tester.takeException(), isNull);
      });

      testWidgets('an inactive role detail renders in $mode', (
        WidgetTester tester,
      ) async {
        await pumpApp(
          tester,
          initialUser: testUser,
          portalResult: resolvedResult(PortalKind.vendorSuperAdmin),
          themeMode: mode,
        );
        await goTo(tester, VendorNavigation.roles);
        await tapVisible(tester, find.text('Legacy Auditor'));

        expect(find.byType(VendorRoleDetailPage), findsOneWidget);
        expect(find.text(VendorRoleCopy.inactiveNoticeTitle), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
