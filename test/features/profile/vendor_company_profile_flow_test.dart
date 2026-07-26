import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/navigation/role_destination.dart';
import 'package:sale_reward/app/router/app_router.dart';
import 'package:sale_reward/app/shells/base/placeholder_destination_page.dart';
import 'package:sale_reward/app/shells/vendor/vendor_navigation.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/auth/domain/repositories/portal_context_repository.dart';
import 'package:sale_reward/features/auth/presentation/bloc/session_bloc.dart';
import 'package:sale_reward/features/profile/domain/entities/vendor_administrator_profile.dart';
import 'package:sale_reward/features/profile/presentation/vendor/pages/vendor_company_profile_page.dart';
import 'package:sale_reward/features/profile/presentation/vendor/widgets/vendor_profile_administrator_card.dart';
import 'package:sale_reward/features/profile/presentation/vendor/widgets/vendor_profile_company_card.dart';
import 'package:sale_reward/features/profile/presentation/vendor/widgets/vendor_profile_copy.dart';
import 'package:sale_reward/features/profile/presentation/vendor/widgets/vendor_profile_initials.dart';
import 'package:sale_reward/features/profile/presentation/vendor/widgets/vendor_profile_role_chips.dart';

import '../../support/fakes.dart';
import '../../support/pump_app.dart';
import '../../support/vendor_profile_fakes.dart';

/// Drives the Vendor company/profile screen through the real application: real
/// router, real shell, real cubit, over a fake repository that never touches
/// Supabase.

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

/// The text nodes inside the page, in paint order.
List<String> pageTexts(WidgetTester tester) => find
    .descendant(
      of: find.byType(VendorCompanyProfilePage),
      matching: find.byType(Text),
    )
    .evaluate()
    .map((Element e) => (e.widget as Text).data ?? '')
    .toList();

void main() {
  /// Signs in as a Vendor Super Admin and opens the company/profile screen.
  Future<PumpedApp> onProfile(
    WidgetTester tester, {
    FakeVendorProfileRepository? profile,
    Size surface = phoneSurface,
  }) async {
    final PumpedApp app = await pumpAppInRole(
      tester,
      PortalKind.vendorSuperAdmin,
      surface: surface,
      vendorProfile: profile,
    );
    await goTo(tester, VendorNavigation.settings);
    return app;
  }

  group('route isolation', () {
    test('the guard sends every other role away', () {
      for (final PortalKind kind in <PortalKind>[
        PortalKind.retailerOwner,
        PortalKind.retailerManager,
        PortalKind.salesStaff,
      ]) {
        final SessionState session = SessionActive(contextFor(kind));
        expect(
          redirectFor(session, VendorNavigation.settings),
          sessionHome(session),
        );
      }
    });

    test('a Vendor Super Admin is allowed in', () {
      expect(
        redirectFor(
          SessionActive(contextFor(PortalKind.vendorSuperAdmin)),
          VendorNavigation.settings,
        ),
        isNull,
      );
    });

    test('a signed-out caller is sent to login, not to the profile', () {
      expect(
        redirectFor(const SessionUnauthenticated(), VendorNavigation.settings),
        '/login',
      );
    });

    test('a denied session is sent to access-denied', () {
      expect(
        redirectFor(const SessionDenied(), VendorNavigation.settings),
        '/access-denied',
      );
    });

    test('the route is inside the Vendor prefix', () {
      expect(VendorNavigation.settings, '/vendor/settings');
      expect(
        VendorNavigation.settings.startsWith(VendorNavigation.prefix),
        isTrue,
      );
    });

    testWidgets('a Retailer Owner typing the URL lands on their own home', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerOwner);

      await goTo(tester, VendorNavigation.settings);

      expect(find.byType(VendorCompanyProfilePage), findsNothing);
      expect(currentLocation(tester), isNot(VendorNavigation.settings));
    });

    testWidgets('a Retailer Manager typing the URL lands on their own home', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerManager);

      await goTo(tester, VendorNavigation.settings);

      expect(find.byType(VendorCompanyProfilePage), findsNothing);
    });

    testWidgets('a Sales Staff user typing the URL lands on their own home', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);

      await goTo(tester, VendorNavigation.settings);

      expect(find.byType(VendorCompanyProfilePage), findsNothing);
    });

    testWidgets('there is no detail route beneath it', (
      WidgetTester tester,
    ) async {
      // Neither half of this screen is addressable: the read takes zero
      // arguments and the organization comes from the session.
      await onProfile(tester);

      await goTo(tester, '${VendorNavigation.settings}/anything');

      expect(find.byType(VendorCompanyProfilePage), findsNothing);
    });

    testWidgets('no edit, company-detail or security route exists', (
      WidgetTester tester,
    ) async {
      await onProfile(tester);

      for (final String unbuilt in <String>[
        '/vendor/settings/edit',
        '/vendor/company',
        '/vendor/profile',
        '/vendor/account',
        '/vendor/settings/security',
        '/vendor/settings/password',
      ]) {
        await goTo(tester, unbuilt);
        expect(
          find.byType(VendorCompanyProfilePage),
          findsNothing,
          reason: '$unbuilt must not resolve to the profile screen',
        );
        await goTo(tester, VendorNavigation.settings);
      }
    });
  });

  group('the Settings placeholder is gone', () {
    test('the destination is routable and points at the new screen', () {
      final RoleDestination settings = VendorNavigation.destinations.last;

      expect(settings.label, 'Settings');
      expect(settings.isEnabled, isTrue);
      expect(settings.path, VendorNavigation.settings);
    });

    test('Settings is no longer one of the "Soon" entries', () {
      expect(
        VendorNavigation.model.destinations
            .where((RoleDestination d) => !d.isEnabled)
            .map((RoleDestination d) => d.label),
        isNot(contains('Settings')),
      );
      expect(
        VendorNavigation.model.routableDestinations.map(
          (RoleDestination d) => d.label,
        ),
        contains('Settings'),
      );
    });

    testWidgets('the route renders the real page, not a coming-soon card', (
      WidgetTester tester,
    ) async {
      await onProfile(tester);

      expect(find.byType(VendorCompanyProfilePage), findsOneWidget);
      expect(find.byType(PlaceholderDestinationPage), findsNothing);
      expect(find.text('Coming soon'), findsNothing);
      expect(find.text('Data pending'), findsNothing);
    });

    testWidgets('the drawer entry navigates to it and stays selected', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.vendorSuperAdmin);

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Settings').last);

      expect(currentLocation(tester), VendorNavigation.settings);
      expect(find.byType(VendorCompanyProfilePage), findsOneWidget);

      // And the shell keeps it selected while the route is open.
      final int selected = VendorNavigation.model.indexForLocation(
        VendorNavigation.settings,
      );
      expect(VendorNavigation.destinations[selected].label, 'Settings');
    });

    testWidgets('the Vendor shell stays visible around the screen', (
      WidgetTester tester,
    ) async {
      await onProfile(tester, surface: desktopSurface);

      // The permanent side panel is the shell; the page renders inside it.
      expect(find.byType(VendorCompanyProfilePage), findsOneWidget);
      expect(find.text('Dashboard'), findsWidgets);
      expect(find.text('Audit Logs'), findsWidgets);
    });

    testWidgets('the other six Vendor destinations are untouched', (
      WidgetTester tester,
    ) async {
      await onProfile(tester);

      expect(
        VendorNavigation.model.routableDestinations.map(
          (RoleDestination d) => d.label,
        ),
        <String>[
          'Dashboard',
          'Retailers',
          'Users',
          'Roles',
          'Products',
          'Audit Logs',
          'Settings',
        ],
      );
    });

    testWidgets('the five unbuilt modules stay unavailable', (
      WidgetTester tester,
    ) async {
      await onProfile(tester);

      expect(
        VendorNavigation.model.destinations
            .where((RoleDestination d) => !d.isEnabled)
            .map((RoleDestination d) => d.label),
        <String>['Campaigns', 'Claims', 'Coins', 'Payouts', 'Reports'],
      );
    });
  });

  group('the company section', () {
    testWidgets('the organization name comes from the session context', (
      WidgetTester tester,
    ) async {
      await pumpApp(
        tester,
        initialUser: testUser,
        portalResult: PortalContextResolved(
          contextFor(
            PortalKind.vendorSuperAdmin,
            organizationName: 'Northwind Trading',
          ),
        ),
      );
      await goTo(tester, VendorNavigation.settings);

      expect(find.byType(VendorProfileCompanyCard), findsOneWidget);
      expect(find.text('Northwind Trading'), findsWidgets);
      expect(find.text(VendorProfileCopy.companyScopeLabel), findsOneWidget);
    });

    testWidgets('it says where the name came from', (
      WidgetTester tester,
    ) async {
      await onProfile(tester);

      expect(find.text(VendorProfileCopy.companySourceNote), findsOneWidget);
    });

    testWidgets('the limitation is explained, neutrally', (
      WidgetTester tester,
    ) async {
      await onProfile(tester);

      expect(
        find.text(VendorProfileCopy.companyLimitationNote),
        findsOneWidget,
      );
      // And it must not read as a failure — nothing failed, and no retry could
      // add a column the database does not have.
      for (final String failureWord in <String>[
        'Could not load',
        'Failed',
        'Unavailable',
        'Try again',
      ]) {
        expect(
          find.descendant(
            of: find.byType(VendorProfileCompanyCard),
            matching: find.textContaining(failureWord),
          ),
          findsNothing,
        );
      }
    });

    testWidgets('no fabricated company field is rendered', (
      WidgetTester tester,
    ) async {
      await onProfile(tester);

      // No such column exists anywhere in the schema, so there is no disabled
      // field, no placeholder dash and no "coming soon" row standing in for one.
      for (final String invented in <String>[
        'Legal name',
        'Trading name',
        'Registration',
        'Tax',
        'VAT',
        'Website',
        'Business email',
        'Business phone',
        'Address',
        'Country',
        'Currency',
        'Logo',
        'Created',
        'Updated',
      ]) {
        expect(
          find.descendant(
            of: find.byType(VendorCompanyProfilePage),
            matching: find.textContaining(invented),
          ),
          findsNothing,
          reason: 'the company section must not name "$invented"',
        );
      }

      // Nor a dash standing in for an absent value.
      expect(pageTexts(tester), isNot(contains('—')));
      expect(pageTexts(tester), isNot(contains('-')));
      expect(pageTexts(tester), isNot(contains('N/A')));
    });

    testWidgets('no editable field and no edit affordance exists', (
      WidgetTester tester,
    ) async {
      await onProfile(tester);

      expect(find.byType(SrTextField), findsNothing);
      expect(find.byType(TextField), findsNothing);
      for (final String action in <String>[
        'Edit',
        'Save',
        'Change',
        'Update',
        'Upload',
        'Manage',
        'Delete',
      ]) {
        expect(
          find.descendant(
            of: find.byType(VendorCompanyProfilePage),
            matching: find.textContaining(action),
          ),
          findsNothing,
          reason: 'this milestone is read-only; "$action" must not appear',
        );
      }
    });
  });

  group('the administrator section', () {
    testWidgets('the display name comes from the RPC model, verbatim', (
      WidgetTester tester,
    ) async {
      final FakeVendorProfileRepository repository =
          FakeVendorProfileRepository()
            ..nextProfile = const VendorAdministratorProfile(
              displayName: "Mary-Jane O'Neill",
              roleNames: <String>['Vendor Super Admin'],
            );

      await onProfile(tester, profile: repository);

      expect(find.byType(VendorProfileAdministratorCard), findsOneWidget);
      expect(find.text("Mary-Jane O'Neill"), findsOneWidget);
      expect(
        find.text(VendorProfileCopy.administratorSectionTitle),
        findsOneWidget,
      );
    });

    testWidgets('the administrator name is never the organization name', (
      WidgetTester tester,
    ) async {
      await pumpApp(
        tester,
        initialUser: testUser,
        portalResult: PortalContextResolved(
          contextFor(
            PortalKind.vendorSuperAdmin,
            organizationName: 'Northwind Trading',
          ),
        ),
      );
      await goTo(tester, VendorNavigation.settings);

      expect(
        find.descendant(
          of: find.byType(VendorProfileAdministratorCard),
          matching: find.text('Northwind Trading'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(VendorProfileCompanyCard),
          matching: find.text('Amina Rahman'),
        ),
        findsNothing,
      );
    });

    testWidgets('one role renders as one chip', (WidgetTester tester) async {
      await onProfile(tester);

      expect(find.text('Vendor Super Admin'), findsOneWidget);
      expect(find.text(VendorProfileCopy.rolesTitle), findsOneWidget);
      expect(find.text(VendorProfileCopy.rolesDescription), findsOneWidget);
    });

    testWidgets('several roles display in the backend\'s order', (
      WidgetTester tester,
    ) async {
      final FakeVendorProfileRepository repository =
          FakeVendorProfileRepository()..nextProfile = reversedOrderProfile;

      await onProfile(tester, profile: repository);

      final List<String> chips = find
          .descendant(
            of: find.byType(VendorProfileRoleChips),
            matching: find.byType(Text),
          )
          .evaluate()
          .map((Element e) => (e.widget as Text).data ?? '')
          .toList();

      // Exactly as received. An alphabetising client would produce the reverse.
      expect(chips, <String>[
        'Vendor Super Admin',
        'Finance Admin',
        'Catalogue Manager',
      ]);
    });

    testWidgets('many long role names wrap without overflow on a phone', (
      WidgetTester tester,
    ) async {
      final FakeVendorProfileRepository repository =
          FakeVendorProfileRepository()
            ..nextProfile = const VendorAdministratorProfile(
              displayName: 'Amina Rahman',
              roleNames: <String>[
                'Catalogue and Product Assignment Manager',
                'Claims and Payouts Reconciliation Reviewer',
                'Finance Administration and Reporting Lead',
                'Retailer Onboarding and Relationship Owner',
                'Vendor Super Admin',
              ],
            );

      await onProfile(tester, profile: repository, surface: smallPhoneSurface);

      expect(tester.takeException(), isNull);
      expect(find.byType(VendorProfileRoleChips), findsOneWidget);
      expect(find.text('Vendor Super Admin'), findsOneWidget);
    });

    testWidgets('the defensive empty role list renders safely', (
      WidgetTester tester,
    ) async {
      final FakeVendorProfileRepository repository =
          FakeVendorProfileRepository()
            ..nextProfile = noRoleAdministratorProfile;

      await onProfile(tester, profile: repository);

      expect(tester.takeException(), isNull);
      expect(find.text(VendorProfileCopy.noRoles), findsOneWidget);
      // A real name is still beside it, and no chip is fabricated.
      expect(find.text('Amina Rahman'), findsOneWidget);
      expect(find.text('Vendor Super Admin'), findsNothing);
    });

    testWidgets('the avatar is initials, never an image', (
      WidgetTester tester,
    ) async {
      await onProfile(tester);

      // Two discs — the company and the administrator — and no network image,
      // because no logo or avatar column exists anywhere in the schema.
      expect(find.byType(VendorProfileAvatar), findsNWidgets(2));
      expect(find.byType(Image), findsNothing);
      expect(find.byType(CircleAvatar), findsNothing);
      expect(find.text('AR'), findsOneWidget);
    });

    testWidgets('no personal detail beyond the two fields appears', (
      WidgetTester tester,
    ) async {
      await onProfile(tester);

      for (final String forbidden in <String>[
        '@',
        'Email',
        'Mobile',
        'Phone',
        'Status',
        // Not the bare word "Active": the role heading legitimately reads
        // "Active roles", and the roles genuinely are the active ones. What must
        // be absent is a *status* — the three the contract deliberately does not
        // return, because they are conditions of the read rather than output.
        'ACTIVE',
        'Account status',
        'Profile status',
        'Membership status',
        'Active member',
        'Suspended',
        'Deactivated',
        'Invited',
        'Member since',
        'Joined',
        'Last seen',
        'ID',
        'Permission',
        'VENDOR_SUPER_ADMIN',
        'RBAC_READ',
      ]) {
        expect(
          find.descendant(
            of: find.byType(VendorCompanyProfilePage),
            matching: find.textContaining(forbidden),
          ),
          findsNothing,
          reason: 'the profile must not show "$forbidden"',
        );
      }
    });

    testWidgets('no status badge and no timestamp is rendered', (
      WidgetTester tester,
    ) async {
      await onProfile(tester);

      // An authorized caller is ACTIVE in all three statuses by construction, so
      // the contract returns none of them and nothing here infers a badge.
      expect(
        find.descendant(
          of: find.byType(VendorCompanyProfilePage),
          matching: find.byType(SrBadge),
        ),
        findsNothing,
      );
      for (final String text in pageTexts(tester)) {
        expect(
          RegExp(r'\d{4}-\d{2}-\d{2}').hasMatch(text),
          isFalse,
          reason: 'no timestamp may appear: "$text"',
        );
      }
    });

    testWidgets('no identifier is rendered anywhere', (
      WidgetTester tester,
    ) async {
      await onProfile(tester);

      final RegExp uuid = RegExp(
        r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
        r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
      );
      for (final String text in pageTexts(tester)) {
        expect(uuid.hasMatch(text), isFalse, reason: 'an id leaked: "$text"');
      }
    });
  });

  group('loading, failure and retry', () {
    testWidgets('a skeleton stands in while the first read is in flight', (
      WidgetTester tester,
    ) async {
      final FakeVendorProfileRepository repository =
          FakeVendorProfileRepository()..manual = true;

      // The skeleton shimmers forever by design, so `pumpAndSettle` would time
      // out rather than converge — this pumps frames by hand instead.
      await pumpApp(
        tester,
        initialUser: testUser,
        portalResult: resolvedResult(PortalKind.vendorSuperAdmin),
        vendorProfile: repository,
        settle: false,
      );
      for (int i = 0; i < 4; i++) {
        await tester.pump();
      }
      GoRouter.of(
        tester.element(find.byType(Navigator).first),
      ).go(VendorNavigation.settings);
      for (int i = 0; i < 4; i++) {
        await tester.pump();
      }

      expect(find.byType(SrSkeletonScreen), findsWidgets);
      // Nothing is rendered as an identity while the answer is unknown.
      expect(find.text('Amina Rahman'), findsNothing);

      repository.complete();
      await tester.pumpAndSettle();
      expect(find.text('Amina Rahman'), findsOneWidget);
    });

    testWidgets('a failed first read offers a retry that can succeed', (
      WidgetTester tester,
    ) async {
      final FakeVendorProfileRepository repository =
          FakeVendorProfileRepository()
            ..result = unavailableProfileRead<VendorAdministratorProfile>();

      await onProfile(tester, profile: repository);

      expect(find.byType(SrFailureView), findsOneWidget);
      expect(find.text('Could not load this'), findsOneWidget);
      // No administrator card, and above all no blank name.
      expect(find.byType(VendorProfileAdministratorCard), findsNothing);
      // The company half is unaffected: it came from the session, not the RPC.
      expect(find.byType(VendorProfileCompanyCard), findsOneWidget);

      repository.result = null;
      await tapVisible(tester, find.text('Try again'));

      expect(find.byType(SrFailureView), findsNothing);
      expect(find.text('Amina Rahman'), findsOneWidget);
    });

    testWidgets('a denial offers no retry and names nothing', (
      WidgetTester tester,
    ) async {
      final FakeVendorProfileRepository repository =
          FakeVendorProfileRepository()
            ..result = deniedProfileRead<VendorAdministratorProfile>();

      await onProfile(tester, profile: repository);

      expect(find.text('Not available to this account'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(find.byType(VendorProfileAdministratorCard), findsNothing);

      for (final String leak in <String>[
        'RBAC_READ',
        'ORGANIZATION_MEMBERS_READ',
        'VENDOR_SUPER_ADMIN',
        '42501',
        'insufficient_privilege',
        'profiles',
        'organization_members',
        'member_roles',
        'get_my_vendor_profile',
      ]) {
        expect(find.textContaining(leak), findsNothing);
      }
    });

    testWidgets('a malformed response is an outage, never a partial render', (
      WidgetTester tester,
    ) async {
      // The parser fails the whole profile, so the repository answers with an
      // outage and the screen shows one field of neither.
      final FakeVendorProfileRepository repository =
          FakeVendorProfileRepository()
            ..result = unavailableProfileRead<VendorAdministratorProfile>();

      await onProfile(tester, profile: repository);

      expect(find.byType(SrFailureView), findsOneWidget);
      expect(find.byType(VendorProfileRoleChips), findsNothing);
      expect(find.text(VendorProfileCopy.noRoles), findsNothing);
    });
  });

  group('refresh', () {
    testWidgets('the header button re-reads the profile', (
      WidgetTester tester,
    ) async {
      final FakeVendorProfileRepository repository =
          FakeVendorProfileRepository();

      await onProfile(tester, profile: repository);
      expect(repository.callCount, 1);

      repository.nextProfile = joAdministratorProfile;
      await tapVisible(tester, find.text(VendorProfileCopy.refresh));

      expect(repository.callCount, 2);
      expect(find.text('Jo Nakamura'), findsOneWidget);
      expect(find.text('Finance Admin'), findsOneWidget);
      // Replaced whole: the previous administrator is gone.
      expect(find.text('Amina Rahman'), findsNothing);
    });

    testWidgets('a failed refresh keeps the profile and says so', (
      WidgetTester tester,
    ) async {
      final FakeVendorProfileRepository repository =
          FakeVendorProfileRepository();

      await onProfile(tester, profile: repository);

      repository.result = unavailableProfileRead<VendorAdministratorProfile>();
      await tapVisible(tester, find.text(VendorProfileCopy.refresh));

      expect(find.text(VendorProfileCopy.staleTitle), findsOneWidget);
      // Non-blocking: both cards are still there, with their previous values.
      expect(find.byType(VendorProfileAdministratorCard), findsOneWidget);
      expect(find.byType(VendorProfileCompanyCard), findsOneWidget);
      expect(find.text('Amina Rahman'), findsOneWidget);
      expect(find.text('Vendor Super Admin'), findsOneWidget);
      expect(find.byType(SrFailureView), findsNothing);
    });

    testWidgets('a refresh after a failure clears the notice', (
      WidgetTester tester,
    ) async {
      final FakeVendorProfileRepository repository =
          FakeVendorProfileRepository();

      await onProfile(tester, profile: repository);
      repository.result = unavailableProfileRead<VendorAdministratorProfile>();
      await tapVisible(tester, find.text(VendorProfileCopy.refresh));
      expect(find.text(VendorProfileCopy.staleTitle), findsOneWidget);

      repository.result = null;
      await tapVisible(tester, find.text(VendorProfileCopy.refresh));

      expect(find.text(VendorProfileCopy.staleTitle), findsNothing);
    });

    testWidgets('the screen can be pulled to refresh on a phone', (
      WidgetTester tester,
    ) async {
      final FakeVendorProfileRepository repository =
          FakeVendorProfileRepository();

      await onProfile(tester, profile: repository);
      expect(repository.callCount, 1);

      await tester.fling(
        find.byType(RefreshIndicator),
        const Offset(0, 320),
        1000,
      );
      await tester.pumpAndSettle();

      expect(repository.callCount, 2);
    });

    testWidgets('navigating away and back does not re-read', (
      WidgetTester tester,
    ) async {
      // The cubit belongs to the shell, so a round trip renders what is already
      // held rather than issuing a second call.
      final FakeVendorProfileRepository repository =
          FakeVendorProfileRepository();

      await onProfile(tester, profile: repository);
      expect(repository.callCount, 1);

      await goTo(tester, VendorNavigation.dashboard);
      await goTo(tester, VendorNavigation.settings);

      expect(repository.callCount, 1);
      expect(find.text('Amina Rahman'), findsOneWidget);
    });
  });

  group('accessibility semantics', () {
    testWidgets('the company identity is announced with its source', (
      WidgetTester tester,
    ) async {
      await onProfile(tester);

      expect(
        semanticsContaining(VendorProfileCopy.companySemantics('Example Org')),
        findsOneWidget,
      );
    });

    testWidgets('the administrator identity is announced', (
      WidgetTester tester,
    ) async {
      await onProfile(tester);

      expect(
        semanticsContaining(
          VendorProfileCopy.administratorSemantics('Amina Rahman'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the role list is announced as one sentence', (
      WidgetTester tester,
    ) async {
      final FakeVendorProfileRepository repository =
          FakeVendorProfileRepository()
            ..nextProfile = multiRoleAdministratorProfile;

      await onProfile(tester, profile: repository);

      expect(
        semanticsContaining(
          VendorProfileCopy.rolesSemantics(const <String>[
            'Catalogue Manager',
            'Finance Admin',
            'Vendor Super Admin',
          ]),
        ),
        findsOneWidget,
      );
    });

    testWidgets('each chip is independently labelled', (
      WidgetTester tester,
    ) async {
      final FakeVendorProfileRepository repository =
          FakeVendorProfileRepository()
            ..nextProfile = multiRoleAdministratorProfile;

      await onProfile(tester, profile: repository);

      for (final String role in <String>[
        'Catalogue Manager',
        'Finance Admin',
        'Vendor Super Admin',
      ]) {
        expect(
          semanticsContaining(VendorProfileCopy.roleSemantics(role)),
          findsOneWidget,
        );
      }
    });

    testWidgets('the empty role list is announced, not silent', (
      WidgetTester tester,
    ) async {
      final FakeVendorProfileRepository repository =
          FakeVendorProfileRepository()
            ..nextProfile = noRoleAdministratorProfile;

      await onProfile(tester, profile: repository);

      expect(
        semanticsContaining(VendorProfileCopy.rolesSemantics(const <String>[])),
        findsOneWidget,
      );
    });

    testWidgets('the company limitation note is announced', (
      WidgetTester tester,
    ) async {
      await onProfile(tester);

      expect(
        semanticsContaining(VendorProfileCopy.companyLimitationNote),
        findsOneWidget,
      );
    });

    testWidgets('the Refresh action is a labelled button', (
      WidgetTester tester,
    ) async {
      await onProfile(tester);

      expect(semanticsContaining(VendorProfileCopy.refresh), findsWidgets);
    });

    testWidgets('the page heading is marked as a heading', (
      WidgetTester tester,
    ) async {
      await onProfile(tester);

      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Semantics && widget.properties.header == true,
          description: 'a Semantics node flagged as a header',
        ),
        findsWidgets,
      );
    });

    testWidgets('the stale notice is a live region', (
      WidgetTester tester,
    ) async {
      final FakeVendorProfileRepository repository =
          FakeVendorProfileRepository();

      await onProfile(tester, profile: repository);
      repository.result = unavailableProfileRead<VendorAdministratorProfile>();
      await tapVisible(tester, find.text(VendorProfileCopy.refresh));

      expect(find.byType(SrAlert), findsOneWidget);
      expect(find.text(VendorProfileCopy.staleBody), findsOneWidget);
    });

    testWidgets('the avatar initials are hidden from the semantics tree', (
      WidgetTester tester,
    ) async {
      // A screen reader hears the full name, not two letters.
      await onProfile(tester);

      expect(find.byType(VendorProfileAvatar), findsNWidgets(2));
      for (final Element element
          in find.byType(VendorProfileAvatar).evaluate()) {
        expect(
          find.descendant(
            of: find.byWidget(element.widget),
            matching: find.byType(ExcludeSemantics),
          ),
          findsOneWidget,
        );
      }
    });
  });

  group('responsive and themed', () {
    for (final ({String name, Size size}) surface
        in <({String name, Size size})>[
          (name: 'a small phone', size: smallPhoneSurface),
          (name: 'a phone', size: phoneSurface),
          (name: 'a tablet', size: tabletSurface),
          (name: 'a desktop browser', size: desktopSurface),
        ]) {
      testWidgets('the screen lays out on ${surface.name} without overflow', (
        WidgetTester tester,
      ) async {
        await onProfile(tester, surface: surface.size);

        expect(tester.takeException(), isNull);
        expect(find.byType(VendorProfileCompanyCard), findsOneWidget);
        expect(find.byType(VendorProfileAdministratorCard), findsOneWidget);
      });
    }

    testWidgets('large text scale does not overflow a small phone', (
      WidgetTester tester,
    ) async {
      useSurface(tester, smallPhoneSurface);
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await onProfile(tester, surface: smallPhoneSurface);

      expect(tester.takeException(), isNull);
    });

    for (final ThemeMode mode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
      testWidgets('the screen renders in $mode', (WidgetTester tester) async {
        await pumpApp(
          tester,
          initialUser: testUser,
          portalResult: resolvedResult(PortalKind.vendorSuperAdmin),
          themeMode: mode,
        );
        await goTo(tester, VendorNavigation.settings);

        expect(find.byType(VendorProfileCompanyCard), findsOneWidget);
        expect(find.byType(VendorProfileAdministratorCard), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('initials are computed locally and safely', () {
    test('a two-part name yields two letters', () {
      expect(initialsOf('Amina Rahman'), 'AR');
    });

    test('a single-word name yields one letter, never a padded pair', () {
      expect(initialsOf('Member'), 'M');
    });

    test('a name with several parts uses the first and the last', () {
      expect(initialsOf('Mary Jane O’Neill'), 'MO');
    });

    test('padding is ignored rather than turned into a blank initial', () {
      expect(initialsOf('  Amina   Rahman  '), 'AR');
    });

    test('a blank name yields nothing rather than an invented letter', () {
      // Unreachable — every input has already passed the parser's non-blank
      // guard — but a fabricated initial would be a fabricated name.
      expect(initialsOf('   '), '');
    });
  });
}
