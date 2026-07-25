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
import 'package:sale_reward/features/users/domain/entities/vendor_user_detail.dart';
import 'package:sale_reward/features/users/domain/entities/vendor_user_summary.dart';
import 'package:sale_reward/features/users/presentation/vendor/pages/vendor_user_detail_page.dart';
import 'package:sale_reward/features/users/presentation/vendor/pages/vendor_users_page.dart';
import 'package:sale_reward/features/users/presentation/vendor/widgets/vendor_user_card.dart';
import 'package:sale_reward/features/users/presentation/vendor/widgets/vendor_user_copy.dart';

import '../../support/fakes.dart';
import '../../support/pump_app.dart';
import '../../support/vendor_user_fakes.dart';

/// Drives the Vendor User screens through the real application: real router,
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
  /// Signs in as a Vendor Super Admin and opens the Users directory.
  Future<PumpedApp> onDirectory(
    WidgetTester tester, {
    FakeVendorUserRepository? users,
    Size surface = phoneSurface,
  }) async {
    final PumpedApp app = await pumpAppInRole(
      tester,
      PortalKind.vendorSuperAdmin,
      surface: surface,
      vendorUsers: users,
    );
    await goTo(tester, VendorNavigation.users);
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

        expect(redirectFor(session, VendorNavigation.users), home);
        expect(
          redirectFor(
            session,
            VendorNavigation.userDetailPath(aminaMembershipUuid),
          ),
          home,
        );
      }
    });

    test('a Vendor Super Admin is allowed into both', () {
      final SessionState session = SessionActive(
        contextFor(PortalKind.vendorSuperAdmin),
      );

      expect(redirectFor(session, VendorNavigation.users), isNull);
      expect(
        redirectFor(
          session,
          VendorNavigation.userDetailPath(aminaMembershipUuid),
        ),
        isNull,
      );
    });

    test('a signed-out caller is sent to login, not to the directory', () {
      expect(
        redirectFor(const SessionUnauthenticated(), VendorNavigation.users),
        '/login',
      );
    });

    test('the detail route is the membership id under the Users path', () {
      expect(
        VendorNavigation.userDetailPath(aminaMembershipUuid),
        '/vendor/users/$aminaMembershipUuid',
      );
      expect(
        VendorNavigation.userDetailPath(
          aminaMembershipUuid,
        ).startsWith(VendorNavigation.users),
        isTrue,
      );
    });

    test('Users stays the selected destination for list and detail', () {
      // Longest-prefix wins, so an open user does not fall back to Dashboard.
      final RoleNavigation model = VendorNavigation.model;
      final int usersIndex = model.destinations.indexWhere(
        (RoleDestination d) => d.path == VendorNavigation.users,
      );

      expect(model.indexForLocation(VendorNavigation.users), usersIndex);
      expect(
        model.indexForLocation(
          VendorNavigation.userDetailPath(aminaMembershipUuid),
        ),
        usersIndex,
      );
    });

    testWidgets('a Retailer Owner cannot reach the Vendor User routes', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerOwner);

      await goTo(tester, VendorNavigation.users);
      expect(find.byType(VendorUsersPage), findsNothing);

      await goTo(tester, VendorNavigation.userDetailPath(aminaMembershipUuid));
      expect(find.byType(VendorUserDetailPage), findsNothing);
      expect(currentLocation(tester), RetailerOwnerNavigation.overview);
    });

    testWidgets('a Retailer Manager cannot reach them either', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerManager);

      await goTo(tester, VendorNavigation.userDetailPath(aminaMembershipUuid));

      expect(find.byType(VendorUserDetailPage), findsNothing);
      expect(currentLocation(tester), RetailerManagerNavigation.staff);
    });

    testWidgets('Sales Staff cannot reach them either', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);

      await goTo(tester, VendorNavigation.users);

      expect(find.byType(VendorUsersPage), findsNothing);
      expect(currentLocation(tester), SalesStaffNavigation.submit);
    });

    testWidgets('no other role even reads the Vendor User RPCs', (
      WidgetTester tester,
    ) async {
      final FakeVendorUserRepository repository = FakeVendorUserRepository();

      await pumpAppInRole(
        tester,
        PortalKind.retailerOwner,
        vendorUsers: repository,
      );
      await goTo(tester, VendorNavigation.users);

      // The shell that owns the cubits is never built for this role.
      expect(repository.usersCallCount, 0);
      expect(repository.detailCallCount, 0);
    });
  });

  group('the directory', () {
    testWidgets('a Vendor Super Admin reaches it and sees their colleagues', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onDirectory(tester);

      expect(find.byType(VendorUsersPage), findsOneWidget);
      expect(find.text('Amina Rahman'), findsOneWidget);
      expect(find.text('Jo Nakamura'), findsOneWidget);
      // One read for the whole screen, and no detail opened.
      expect(app.vendorUsers.usersCallCount, 1);
      expect(app.vendorUsers.detailCallCount, 0);
    });

    testWidgets('nothing is read until the directory is actually opened', (
      WidgetTester tester,
    ) async {
      // `BlocProvider` builds each cubit on first read, so landing in the Vendor
      // shell fetches neither directory — and opening Retailers never fetches
      // Users. Pinned as a test because the shell's doc comment claims it.
      final FakeVendorUserRepository repository = FakeVendorUserRepository();
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.vendorSuperAdmin,
        vendorUsers: repository,
      );

      expect(repository.usersCallCount, 0);
      expect(app.retailers.retailersCallCount, 0);

      await goTo(tester, VendorNavigation.retailers);
      expect(repository.usersCallCount, 0);
      expect(app.retailers.retailersCallCount, 1);

      await goTo(tester, VendorNavigation.users);
      expect(repository.usersCallCount, 1);
      expect(app.retailers.retailersCallCount, 1);
    });

    testWidgets('shows a loading skeleton before the first answer', (
      WidgetTester tester,
    ) async {
      final FakeVendorUserRepository repository = FakeVendorUserRepository()
        ..manualUsers = true;

      await pumpAppInRole(
        tester,
        PortalKind.vendorSuperAdmin,
        vendorUsers: repository,
      );
      GoRouter.of(
        tester.element(find.byType(Navigator).first),
      ).go(VendorNavigation.users);
      // Two frames: one for the router to swap the route, one for the page to
      // build. Deliberately not pumpAndSettle — the skeleton shimmers forever.
      await tester.pump();
      await tester.pump();

      expect(find.byType(SrLoadingView), findsOneWidget);
      expect(find.byType(VendorUserCard), findsNothing);

      repository.completeUsers();
      await tester.pumpAndSettle();

      expect(find.byType(SrLoadingView), findsNothing);
      expect(find.byType(VendorUserCard), findsNWidgets(2));
    });

    testWidgets('every row is visibly actionable', (WidgetTester tester) async {
      await onDirectory(tester);

      expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(2));
      expect(find.text(VendorUserCopy.openDetails), findsNWidgets(2));
      for (final VendorUserCard card in tester.widgetList<VendorUserCard>(
        find.byType(VendorUserCard),
      )) {
        expect(card.onOpen, isNotNull);
      }
    });

    testWidgets('both statuses are shown, and named', (
      WidgetTester tester,
    ) async {
      await onDirectory(tester);

      expect(find.text('Profile: Active'), findsOneWidget);
      expect(find.text('Membership: Active'), findsOneWidget);
      expect(find.text('Profile: Invited'), findsOneWidget);
      expect(find.text('Membership: Invited'), findsOneWidget);
    });

    testWidgets('role chips render, and a no-role user says so', (
      WidgetTester tester,
    ) async {
      await onDirectory(tester);

      expect(find.text('Finance Admin'), findsOneWidget);
      expect(find.text('Vendor Super Admin'), findsOneWidget);
      expect(find.text('2 roles'), findsOneWidget);
      // The empty array, worded exactly as the web words it — and never a
      // fabricated default role.
      expect(find.text(VendorUserCopy.noRoles), findsNWidgets(2));
    });

    testWidgets('a not-yet-joined user says so rather than showing a date', (
      WidgetTester tester,
    ) async {
      await onDirectory(tester);

      expect(find.text('Joined 15 Jan 2026'), findsOneWidget);
      expect(
        find.text('Joined ${VendorUserCopy.notJoinedYet}'),
        findsOneWidget,
      );
    });

    testWidgets('no email or phone appears anywhere', (
      WidgetTester tester,
    ) async {
      await onDirectory(tester);

      expect(find.textContaining('@'), findsNothing);
      expect(find.textContaining('Email'), findsNothing);
      expect(find.textContaining('Phone'), findsNothing);
      expect(find.textContaining('Mobile'), findsNothing);
    });

    testWidgets('no invite or write affordance exists', (
      WidgetTester tester,
    ) async {
      await onDirectory(tester);

      // There is no Vendor user invitation backend at all, so an affordance —
      // even a disabled one — would advertise a feature that does not exist.
      //
      // Matched as whole action phrases rather than as words: "Invited" is a
      // legitimate *status* and must keep rendering, while "Invite user" is an
      // action that must not exist.
      for (final String forbidden in <String>[
        'Invite user',
        'Invite a user',
        'Resend',
        'Cancel invitation',
        'Add user',
        'Deactivate user',
        'Assign role',
        'Remove role',
        'Edit user',
      ]) {
        expect(
          find.textContaining(forbidden),
          findsNothing,
          reason: 'the directory offers "$forbidden"',
        );
      }
    });

    testWidgets('the card carries a spoken summary and an open hint', (
      WidgetTester tester,
    ) async {
      await onDirectory(tester);

      expect(semanticsContaining('Amina Rahman'), findsWidgets);
      expect(semanticsContaining('Profile status: Active'), findsWidgets);
      expect(semanticsContaining('Membership status: Active'), findsWidgets);
      expect(
        semanticsContaining('Roles: Finance Admin, Vendor Super Admin'),
        findsWidgets,
      );

      final Semantics semantics = tester.widget<Semantics>(
        semanticsContaining('Amina Rahman').first,
      );
      expect(semantics.properties.button, isTrue);
      expect(semantics.properties.hint, VendorUserCopy.openDetails);
      // The membership id is an address, not display data.
      expect(semantics.properties.label, isNot(contains(aminaMembershipUuid)));
    });

    testWidgets('the totals come from the returned statuses', (
      WidgetTester tester,
    ) async {
      await onDirectory(tester);

      expect(find.text(VendorUserCopy.totalLabel), findsOneWidget);
      expect(find.text(VendorUserCopy.activeLabel), findsOneWidget);
      expect(find.text(VendorUserCopy.invitedLabel), findsOneWidget);
      // Nothing is suspended or deactivated in the fixture, so that card is not
      // shown at all rather than showing a zero.
      expect(find.text(VendorUserCopy.inactiveLabel), findsNothing);
    });

    testWidgets('a one-user directory says it is just you', (
      WidgetTester tester,
    ) async {
      final FakeVendorUserRepository repository = FakeVendorUserRepository()
        ..usersResult = ReadSuccess<List<VendorUserSummary>>(
          <VendorUserSummary>[aminaSummary],
        );

      await onDirectory(tester, users: repository);

      expect(find.byType(VendorUserCard), findsOneWidget);
      expect(find.text(VendorUserCopy.onlyMeTitle), findsOneWidget);
    });

    testWidgets('an empty response is handled safely', (
      WidgetTester tester,
    ) async {
      // Not reachable while authorized, but a defensive floor all the same.
      final FakeVendorUserRepository repository = FakeVendorUserRepository()
        ..usersResult = const ReadSuccess<List<VendorUserSummary>>(
          <VendorUserSummary>[],
        );

      await onDirectory(tester, users: repository);

      expect(find.text(VendorUserCopy.emptyTitle), findsOneWidget);
      expect(find.byType(VendorUserCard), findsNothing);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('a failed first read offers a retry that works', (
      WidgetTester tester,
    ) async {
      final FakeVendorUserRepository repository = FakeVendorUserRepository()
        ..usersResult = unavailableUserRead<List<VendorUserSummary>>();

      await onDirectory(tester, users: repository);

      expect(find.byType(SrFailureView), findsOneWidget);
      expect(find.text('Could not load this'), findsOneWidget);

      repository.usersResult = ReadSuccess<List<VendorUserSummary>>(
        <VendorUserSummary>[aminaSummary],
      );
      await tapVisible(tester, find.text('Try again'));

      expect(find.byType(VendorUserCard), findsOneWidget);
    });

    testWidgets('a denial never offers a retry', (WidgetTester tester) async {
      final FakeVendorUserRepository repository = FakeVendorUserRepository()
        ..usersResult = deniedUserRead<List<VendorUserSummary>>();

      await onDirectory(tester, users: repository);

      expect(find.text('Not available to this account'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('refreshing re-reads without blanking the rows', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onDirectory(tester);

      await tester.tap(find.text(VendorUserCopy.refresh));
      await tester.pump();

      expect(find.byType(VendorUserCard), findsNWidgets(2));

      await tester.pumpAndSettle();
      expect(app.vendorUsers.usersCallCount, 2);
    });

    testWidgets('a failed refresh keeps the rows and warns', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onDirectory(tester);
      app.vendorUsers.usersResult =
          unavailableUserRead<List<VendorUserSummary>>();

      await tapVisible(tester, find.text(VendorUserCopy.refresh));

      expect(find.byType(VendorUserCard), findsNWidgets(2));
      expect(find.text(VendorUserCopy.staleListTitle), findsOneWidget);
    });
  });

  group('search and filtering', () {
    testWidgets('a local search narrows the loaded rows only', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onDirectory(tester);

      await tester.enterText(find.byType(TextField).first, 'amina');
      await tester.pumpAndSettle();

      expect(find.text('Amina Rahman'), findsOneWidget);
      expect(find.text('Jo Nakamura'), findsNothing);
      expect(find.text('Showing 1 of 2'), findsOneWidget);
      // Nothing was sent anywhere.
      expect(app.vendorUsers.usersCallCount, 1);
    });

    testWidgets('a search matching nothing offers a way back', (
      WidgetTester tester,
    ) async {
      await onDirectory(tester);

      await tester.enterText(find.byType(TextField).first, 'zzzz');
      await tester.pumpAndSettle();

      expect(find.text(VendorUserCopy.noMatchesTitle), findsOneWidget);

      await tapVisible(tester, find.text(VendorUserCopy.clearFilters).first);

      expect(find.byType(VendorUserCard), findsNWidgets(2));
    });

    testWidgets('both status filter rows are offered and work', (
      WidgetTester tester,
    ) async {
      await onDirectory(tester, surface: tabletSurface);

      expect(find.text(VendorUserCopy.profileFilterLabel), findsOneWidget);
      expect(find.text(VendorUserCopy.membershipFilterLabel), findsOneWidget);
      // Two chip rows, each with All + Invited + Active.
      expect(find.widgetWithText(SrButton, 'All'), findsNWidgets(2));
      expect(find.widgetWithText(SrButton, 'Invited'), findsNWidgets(2));
      // Nothing is suspended in the fixture, so no chip offers it.
      expect(find.widgetWithText(SrButton, 'Suspended'), findsNothing);

      await tapVisible(tester, find.widgetWithText(SrButton, 'Invited').first);

      expect(find.text('Jo Nakamura'), findsOneWidget);
      expect(find.text('Amina Rahman'), findsNothing);
    });

    testWidgets('filter chips carry their subject in the semantics', (
      WidgetTester tester,
    ) async {
      await onDirectory(tester, surface: tabletSurface);

      expect(
        semanticsContaining('${VendorUserCopy.profileFilterLabel}: Active'),
        findsWidgets,
      );
      expect(
        semanticsContaining('${VendorUserCopy.membershipFilterLabel}: All'),
        findsWidgets,
      );
    });
  });

  group('opening a user', () {
    testWidgets('tapping a row opens its own membership', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onDirectory(tester);

      await tapVisible(tester, find.text('Amina Rahman'));

      expect(find.byType(VendorUserDetailPage), findsOneWidget);
      expect(app.vendorUsers.requestedMembershipIds, <String>[
        aminaMembershipUuid,
      ]);
      expect(
        currentLocation(tester),
        VendorNavigation.userDetailPath(aminaMembershipUuid),
      );
    });

    testWidgets('the detail renders every field the contract returns', (
      WidgetTester tester,
    ) async {
      await onDirectory(tester);
      await tapVisible(tester, find.text('Amina Rahman'));

      expect(find.text('Amina Rahman'), findsOneWidget);
      expect(find.text('Profile: Active'), findsOneWidget);
      expect(find.text('Membership: Active'), findsOneWidget);
      expect(find.text('Finance Admin'), findsOneWidget);
      expect(find.text('Vendor Super Admin'), findsOneWidget);
      expect(find.text('14 Jan 2026'), findsOneWidget);
      expect(find.text('15 Jan 2026'), findsOneWidget);
      // A live membership shows no deactivation row at all.
      expect(find.text(VendorUserCopy.deactivatedLabel), findsNothing);
    });

    testWidgets('a not-yet-joined user shows the neutral phrase', (
      WidgetTester tester,
    ) async {
      await onDirectory(tester);
      await tapVisible(tester, find.text('Jo Nakamura'));

      expect(find.text(VendorUserCopy.notJoinedYet), findsOneWidget);
      expect(find.text(VendorUserCopy.noRoles), findsOneWidget);
      expect(find.text(VendorUserCopy.noRolesBody), findsOneWidget);
    });

    testWidgets('a deactivated membership shows its date', (
      WidgetTester tester,
    ) async {
      final FakeVendorUserRepository repository = FakeVendorUserRepository()
        ..detailResult = ReadSuccess<VendorUserDetail?>(deactivatedDetail);

      await onDirectory(tester, users: repository);
      await tapVisible(tester, find.text('Jo Nakamura'));

      // Twice: the row label, and the membership status value beside it.
      expect(find.text(VendorUserCopy.deactivatedLabel), findsNWidgets(2));
      expect(find.text('20 Jul 2026'), findsOneWidget);
      expect(find.text('Membership: Deactivated'), findsOneWidget);
      expect(find.text('Profile: Suspended'), findsOneWidget);
    });

    testWidgets('no identifier or contact detail is put on screen', (
      WidgetTester tester,
    ) async {
      await onDirectory(tester);
      await tapVisible(tester, find.text('Amina Rahman'));

      expect(find.textContaining(aminaMembershipUuid), findsNothing);
      expect(find.textContaining('@'), findsNothing);
      expect(find.textContaining('Profile ID'), findsNothing);
      expect(find.textContaining('User ID'), findsNothing);
      expect(find.textContaining('Permission'), findsNothing);
    });

    testWidgets('the detail facts are spoken as label-and-value pairs', (
      WidgetTester tester,
    ) async {
      await onDirectory(tester);
      await tapVisible(tester, find.text('Jo Nakamura'));

      expect(
        semanticsContaining(
          '${VendorUserCopy.joinedLabel}: ${VendorUserCopy.notJoinedYet}',
        ),
        findsWidgets,
      );
      expect(
        semanticsContaining('${VendorUserCopy.membershipStatusLabel}: Invited'),
        findsWidgets,
      );
    });

    testWidgets('a detail outage offers a retry that works', (
      WidgetTester tester,
    ) async {
      final FakeVendorUserRepository repository = FakeVendorUserRepository()
        ..detailResult = unavailableUserRead<VendorUserDetail?>();

      await onDirectory(tester, users: repository);
      await tapVisible(tester, find.text('Amina Rahman'));

      expect(find.byType(SrFailureView), findsOneWidget);

      repository.detailResult = null; // back to the id-sensitive default
      await tapVisible(tester, find.text('Try again'));

      expect(find.text('Amina Rahman'), findsOneWidget);
      expect(find.text('Finance Admin'), findsOneWidget);
    });

    testWidgets('going back keeps the directory already loaded', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onDirectory(tester);

      await tapVisible(tester, find.text('Amina Rahman'));
      await tapVisible(tester, find.text(VendorUserCopy.backToList));

      expect(find.byType(VendorUsersPage), findsOneWidget);
      expect(find.byType(VendorUserCard), findsNWidgets(2));
      // No skeleton, and no second directory read.
      expect(app.vendorUsers.usersCallCount, 1);
    });

    testWidgets('a browser-style back pop also returns to the loaded list', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onDirectory(tester);
      await tapVisible(tester, find.text('Amina Rahman'));

      // What the hardware/browser back button drives.
      final NavigatorState navigator = tester.state<NavigatorState>(
        find.byType(Navigator).last,
      );
      navigator.pop();
      await tester.pumpAndSettle();

      expect(find.byType(VendorUsersPage), findsOneWidget);
      expect(find.byType(VendorUserCard), findsNWidgets(2));
      expect(app.vendorUsers.usersCallCount, 1);
    });
  });

  group('a membership this caller may not read', () {
    testWidgets('a manually typed foreign id shows one safe state', (
      WidgetTester tester,
    ) async {
      final FakeVendorUserRepository repository = FakeVendorUserRepository()
        ..detailResult = const ReadSuccess<VendorUserDetail?>(null);

      await onDirectory(tester, users: repository);
      await goTo(
        tester,
        VendorNavigation.userDetailPath(foreignMembershipUuid),
      );

      expect(find.text(VendorUserCopy.detailNotFoundTitle), findsOneWidget);
      // Says nothing about existence or ownership.
      expect(find.textContaining('another Vendor'), findsNothing);
      expect(find.textContaining('Retailer'), findsNothing);
      expect(find.textContaining('exists'), findsNothing);
      // Not an outage: no retry.
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('a malformed id in the URL reaches the same state', (
      WidgetTester tester,
    ) async {
      // The real repository refuses the id shape before any request leaves the
      // client (`vendor_user_repository_test.dart` pins that); what matters here
      // is that the screen it produces is the *same* one a well-formed foreign
      // id produces, so the two are not distinguishable by looking.
      final FakeVendorUserRepository repository = FakeVendorUserRepository()
        ..detailResult = const ReadSuccess<VendorUserDetail?>(null);

      await onDirectory(tester, users: repository);
      await goTo(tester, '${VendorNavigation.users}/not-a-uuid');

      expect(find.text(VendorUserCopy.detailNotFoundTitle), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('the safe state offers a way back to the directory', (
      WidgetTester tester,
    ) async {
      final FakeVendorUserRepository repository = FakeVendorUserRepository()
        ..detailResult = const ReadSuccess<VendorUserDetail?>(null);

      await onDirectory(tester, users: repository);
      await goTo(
        tester,
        VendorNavigation.userDetailPath(foreignMembershipUuid),
      );

      await tapVisible(tester, find.text(VendorUserCopy.backToList).last);

      expect(find.byType(VendorUsersPage), findsOneWidget);
    });
  });

  group('session isolation', () {
    testWidgets('signing out clears the directory', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onDirectory(tester);
      expect(find.text('Amina Rahman'), findsOneWidget);

      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      expect(find.byType(VendorUsersPage), findsNothing);
      expect(find.text('Amina Rahman'), findsNothing);
      expect(find.text('Jo Nakamura'), findsNothing);
      expect(find.text('Finance Admin'), findsNothing);
    });

    testWidgets('an open user is cleared on sign-out too', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onDirectory(tester);
      await tapVisible(tester, find.text('Amina Rahman'));
      expect(find.text('Vendor Super Admin'), findsOneWidget);

      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      expect(find.byType(VendorUserDetailPage), findsNothing);
      expect(find.text('Amina Rahman'), findsNothing);
      expect(find.text('Vendor Super Admin'), findsNothing);
    });

    testWidgets('a new Vendor never sees the previous one\'s users', (
      WidgetTester tester,
    ) async {
      final FakeVendorUserRepository repository = FakeVendorUserRepository();
      final PumpedApp app = await onDirectory(tester, users: repository);
      expect(find.text('Amina Rahman'), findsOneWidget);

      // The next person's directory, under the same role.
      repository.usersResult = ReadSuccess<List<VendorUserSummary>>(
        <VendorUserSummary>[joSummary],
      );
      app.auth.emitSignedIn(secondUser);
      await tester.pumpAndSettle();

      expect(find.text('Amina Rahman'), findsNothing);
      expect(find.text('Finance Admin'), findsNothing);
      expect(find.text('Jo Nakamura'), findsOneWidget);
      expect(repository.usersCallCount, 2);
    });

    testWidgets('a search term does not survive a session change', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onDirectory(tester);
      await tester.enterText(find.byType(TextField).first, 'amina');
      await tester.pumpAndSettle();
      expect(find.text('Showing 1 of 2'), findsOneWidget);

      app.auth.emitSignedIn(secondUser);
      await tester.pumpAndSettle();

      expect(find.text('Showing 1 of 2'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
    });

    testWidgets('the Retailer directory is cleared by the same switch', (
      WidgetTester tester,
    ) async {
      // The shell clears all four cubits together; this pins that the User
      // milestone did not displace the Retailer half of it.
      final PumpedApp app = await onDirectory(tester);
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
      testWidgets('the directory lays out on $name without overflowing', (
        WidgetTester tester,
      ) async {
        await onDirectory(tester, surface: surface);

        expect(find.byType(VendorUserCard), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });

      testWidgets('a user detail lays out on $name without overflowing', (
        WidgetTester tester,
      ) async {
        await onDirectory(tester, surface: surface);
        await tapVisible(tester, find.text('Amina Rahman'));

        expect(find.byType(VendorUserDetailPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('long names and many roles do not overflow a small phone', (
      WidgetTester tester,
    ) async {
      final FakeVendorUserRepository repository = FakeVendorUserRepository()
        ..usersResult = ReadSuccess<List<VendorUserSummary>>(
          <VendorUserSummary>[
            VendorUserSummary(
              membershipId: aminaMembershipUuid,
              displayName: 'Alexandrina Konstantinopoulos-Featherstonehaugh',
              profileStatus: aminaSummary.profileStatus,
              membershipStatus: aminaSummary.membershipStatus,
              membershipCreatedAt: aminaCreatedAt,
              joinedAt: aminaJoinedAt,
              roleNames: const <String>[
                'Vendor Super Administrator With A Very Long Title',
                'Finance And Reconciliation Administrator',
                'Claim Reviewer',
                'Campaign Manager',
                'Report Auditor',
              ],
            ),
          ],
        );

      await onDirectory(tester, users: repository, surface: smallPhoneSurface);

      expect(find.byType(VendorUserCard), findsOneWidget);
      expect(find.text('5 roles'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the directory survives large text scaling', (
      WidgetTester tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await onDirectory(tester, surface: phoneSurface);

      expect(find.byType(VendorUserCard), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide screens use more than one column', (
      WidgetTester tester,
    ) async {
      await onDirectory(tester, surface: desktopSurface);

      final List<Offset> positions = tester
          .widgetList<VendorUserCard>(find.byType(VendorUserCard))
          .map((VendorUserCard card) => tester.getTopLeft(find.byWidget(card)))
          .toList();

      expect(positions[0].dy, positions[1].dy);
      expect(positions[0].dx, lessThan(positions[1].dx));
    });

    testWidgets('a phone stacks the cards', (WidgetTester tester) async {
      await onDirectory(tester, surface: phoneSurface);

      final List<Offset> positions = tester
          .widgetList<VendorUserCard>(find.byType(VendorUserCard))
          .map((VendorUserCard card) => tester.getTopLeft(find.byWidget(card)))
          .toList();

      expect(positions[0].dx, positions[1].dx);
      expect(positions[0].dy, lessThan(positions[1].dy));
    });

    for (final ThemeMode mode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
      testWidgets('the directory renders in $mode', (
        WidgetTester tester,
      ) async {
        await pumpApp(
          tester,
          initialUser: testUser,
          portalResult: resolvedResult(PortalKind.vendorSuperAdmin),
          themeMode: mode,
        );
        await goTo(tester, VendorNavigation.users);

        expect(find.byType(VendorUserCard), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });

      testWidgets('a user detail renders in $mode', (
        WidgetTester tester,
      ) async {
        await pumpApp(
          tester,
          initialUser: testUser,
          portalResult: resolvedResult(PortalKind.vendorSuperAdmin),
          themeMode: mode,
        );
        await goTo(tester, VendorNavigation.users);
        await tapVisible(tester, find.text('Amina Rahman'));

        expect(find.byType(VendorUserDetailPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
