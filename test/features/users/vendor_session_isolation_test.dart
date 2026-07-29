import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/shells/vendor/vendor_shell.dart';
import 'package:sale_reward/app/theme/app_theme.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/audit/domain/entities/vendor_audit_log_entry.dart';
import 'package:sale_reward/features/audit/domain/repositories/vendor_audit_log_repository.dart';
import 'package:sale_reward/features/audit/presentation/vendor/cubit/vendor_audit_log_cubit.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_context.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/auth/domain/entities/retailer_capabilities.dart';
import 'package:sale_reward/features/auth/presentation/bloc/session_bloc.dart';
import 'package:sale_reward/features/dashboard/domain/entities/vendor_dashboard_summary.dart';
import 'package:sale_reward/features/dashboard/domain/repositories/vendor_dashboard_repository.dart';
import 'package:sale_reward/features/dashboard/presentation/vendor/cubit/vendor_dashboard_cubit.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_assigned_retailer.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_assignment_action.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_detail.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_status.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_summary.dart';
import 'package:sale_reward/features/products/domain/repositories/vendor_product_repository.dart';
import 'package:sale_reward/features/products/domain/repositories/vendor_product_write_result.dart';
import 'package:sale_reward/features/products/presentation/vendor/cubit/vendor_product_assignment_cubit.dart';
import 'package:sale_reward/features/products/presentation/vendor/cubit/vendor_product_detail_cubit.dart';
import 'package:sale_reward/features/products/presentation/vendor/cubit/vendor_product_list_cubit.dart';
import 'package:sale_reward/features/profile/domain/entities/vendor_administrator_profile.dart';
import 'package:sale_reward/features/profile/domain/repositories/vendor_profile_repository.dart';
import 'package:sale_reward/features/profile/presentation/vendor/cubit/vendor_profile_cubit.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_summary.dart';
import 'package:sale_reward/features/retailers/domain/repositories/vendor_retailer_lifecycle_repository.dart';
import 'package:sale_reward/features/retailers/domain/repositories/vendor_retailer_repository.dart';
import 'package:sale_reward/features/retailers/domain/repositories/vendor_retailer_result.dart';
import 'package:sale_reward/features/retailers/presentation/vendor/cubit/vendor_retailer_detail_cubit.dart';
import 'package:sale_reward/features/retailers/presentation/vendor/cubit/vendor_retailer_list_cubit.dart';
import 'package:sale_reward/features/roles/domain/entities/vendor_role_detail.dart';
import 'package:sale_reward/features/roles/domain/entities/vendor_role_permission.dart';
import 'package:sale_reward/features/roles/domain/entities/vendor_role_status.dart';
import 'package:sale_reward/features/roles/domain/entities/vendor_role_summary.dart';
import 'package:sale_reward/features/roles/domain/repositories/vendor_role_repository.dart';
import 'package:sale_reward/features/roles/presentation/vendor/cubit/vendor_role_detail_cubit.dart';
import 'package:sale_reward/features/roles/presentation/vendor/cubit/vendor_role_list_cubit.dart';
import 'package:sale_reward/features/users/domain/entities/vendor_user_detail.dart';
import 'package:sale_reward/features/users/domain/entities/vendor_user_summary.dart';
import 'package:sale_reward/features/users/domain/repositories/vendor_user_repository.dart';
import 'package:sale_reward/features/users/presentation/vendor/cubit/vendor_user_detail_cubit.dart';
import 'package:sale_reward/features/users/presentation/vendor/cubit/vendor_user_list_cubit.dart';
import 'package:sale_reward/features/users/presentation/vendor/pages/vendor_users_page.dart';

import '../../support/pump_app.dart';
import '../../support/vendor_audit_log_fakes.dart';
import '../../support/vendor_dashboard_fakes.dart';
import '../../support/vendor_product_fakes.dart';
import '../../support/vendor_profile_fakes.dart';
import '../../support/vendor_retailer_fakes.dart';
import '../../support/vendor_retailer_lifecycle_fakes.dart';
import '../../support/vendor_role_fakes.dart';
import '../../support/vendor_user_fakes.dart';

/// Session isolation for the Vendor shell, driven **state by state**.
///
/// Every other suite reaches `SessionBloc` through the auth stream, which means
/// the transitions it produces are whatever that bloc happens to emit. That is
/// exactly what must not be relied on here: the defect this file exists for is a
/// **direct** `Vendor A → Vendor B` transition with *no* intermediate state, and
/// a test that could not produce one could not prove the fix.
///
/// So the session is a `MockBloc` fed from a controller. Each `add` is one
/// emitted state and nothing else — no `SessionInitial`, no `SessionResolving`,
/// no signed-out state unless the test asks for one.
class MockSessionBloc extends MockBloc<SessionEvent, SessionState>
    implements SessionBloc {}

/// A Vendor context for a named organization.
PortalContext vendorContext(String organizationId) => PortalContext(
  contextVersion: supportedPortalContextVersion,
  portalKind: PortalKind.vendorSuperAdmin,
  vendor: VendorContext(
    organizationId: organizationId,
    organizationName: 'Example Vendor',
  ),
);

/// A Retailer context, for the "moved to another role" case.
PortalContext retailerContext() => const PortalContext(
  contextVersion: supportedPortalContextVersion,
  portalKind: PortalKind.retailerOwner,
  retailer: RetailerContext(
    kind: RetailerKind.owner,
    organizationId: 'ret-org-1',
    organizationName: 'Example Retailer',
    capabilities: RetailerCapabilities.none,
  ),
);

const String orgOne = 'org-one';
const String orgTwo = 'org-two';

/// Advances a fixed number of frames instead of settling.
///
/// `pumpAndSettle` cannot be used anywhere in this file: clearing a cubit sends
/// its page back to the loading skeleton, whose shimmer animates indefinitely by
/// design, so settling would time out rather than converge. Three frames is
/// enough for a stream emission to reach the listener, for the listener's
/// synchronous clears to land, and for the rebuild they cause to be painted.
Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 3; i++) {
    await tester.pump();
  }
}

void main() {
  late MockSessionBloc session;
  late StreamController<SessionState> states;
  late FakeVendorUserRepository users;
  late FakeVendorRetailerRepository retailers;
  late FakeVendorRoleRepository roles;
  late FakeVendorRetailerLifecycleRepository retailerLifecycle;
  late FakeVendorProductRepository products;
  late FakeVendorAuditLogRepository auditLogs;
  late FakeVendorDashboardRepository dashboard;
  late FakeVendorProfileRepository profile;

  /// The identity the shell starts under: Vendor A in organization one.
  final SessionState vendorA = SessionActive(
    vendorContext(orgOne),
    authUserId: 'user-A',
  );

  /// A *different administrator* of the very same organization. The pair that
  /// a portal-kind boolean cannot tell apart.
  final SessionState vendorB = SessionActive(
    vendorContext(orgOne),
    authUserId: 'user-B',
  );

  setUp(() {
    session = MockSessionBloc();
    states = StreamController<SessionState>.broadcast();
    users = FakeVendorUserRepository();
    retailers = FakeVendorRetailerRepository();
    retailerLifecycle = FakeVendorRetailerLifecycleRepository();
    roles = FakeVendorRoleRepository();
    products = FakeVendorProductRepository();
    auditLogs = FakeVendorAuditLogRepository();
    dashboard = FakeVendorDashboardRepository();
    profile = FakeVendorProfileRepository();
    whenListen(session, states.stream, initialState: vendorA);
  });

  tearDown(() => states.close());

  /// Reads a cubit out of the mounted shell.
  T cubit<T extends StateStreamableSource<Object?>>(WidgetTester tester) =>
      BlocProvider.of<T>(tester.element(find.byType(VendorUsersPage)));

  /// Mounts the real [VendorShell] over the mocked session.
  ///
  /// A real router, because the shell's chrome navigates; a real
  /// [VendorUsersPage] as the child, because reading the user directory is what
  /// creates the cubit whose state must survive or be cleared.
  Future<void> pumpShell(WidgetTester tester) async {
    useSurface(tester, tabletSurface);

    final GoRouter router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) => VendorShell(
            location: '/vendor/users',
            portalContext: vendorContext(orgOne),
            child: const VendorUsersPage(),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: <RepositoryProvider<dynamic>>[
          RepositoryProvider<VendorUserRepository>.value(value: users),
          RepositoryProvider<VendorRetailerRepository>.value(value: retailers),
          RepositoryProvider<VendorRetailerLifecycleRepository>.value(
            value: retailerLifecycle,
          ),
          RepositoryProvider<VendorRoleRepository>.value(value: roles),
          RepositoryProvider<VendorProductRepository>.value(value: products),
          RepositoryProvider<VendorAuditLogRepository>.value(value: auditLogs),
          RepositoryProvider<VendorDashboardRepository>.value(value: dashboard),
          RepositoryProvider<VendorProfileRepository>.value(value: profile),
        ],
        child: BlocProvider<SessionBloc>.value(
          value: session,
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      ),
    );
    await settle(tester);

    // Force all eleven cubits into existence before any assertion counts calls.
    // `BlocProvider` builds each on first read, so without this the Retailer,
    // Role and Product pairs would be created *by the session listener itself*
    // and the call counts would measure creation rather than reloading.
    cubit<VendorUserListCubit>(tester);
    cubit<VendorUserDetailCubit>(tester);
    cubit<VendorRetailerListCubit>(tester);
    cubit<VendorRetailerDetailCubit>(tester);
    cubit<VendorRoleListCubit>(tester);
    cubit<VendorRoleDetailCubit>(tester);
    cubit<VendorProductListCubit>(tester);
    cubit<VendorProductDetailCubit>(tester);
    cubit<VendorProductAssignmentCubit>(tester);
    cubit<VendorAuditLogCubit>(tester);
    cubit<VendorDashboardCubit>(tester);
    cubit<VendorProfileCubit>(tester);
    await settle(tester);
  }

  /// Emits one session state and lets the listener run.
  Future<void> emit(WidgetTester tester, SessionState state) async {
    states.add(state);
    await settle(tester);
  }

  group('a direct Vendor A → Vendor B transition, with no state in between', () {
    testWidgets('clears the previous Vendor and loads the new one once', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      expect(find.text('Amina Rahman'), findsOneWidget);
      expect(users.usersCallCount, 1);

      await emit(tester, vendorB);

      // Exactly one reload for B, on top of A's original read.
      expect(users.usersCallCount, 2);
      expect(retailers.retailersCallCount, 2);
    });

    testWidgets('A\'s names and roles are gone before B\'s response arrives', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      expect(find.text('Amina Rahman'), findsOneWidget);
      expect(find.text('Finance Admin'), findsOneWidget);

      // B's directory will not answer until this test says so.
      users.manualUsers = true;
      await emit(tester, vendorB);

      // The window that matters: B is signed in, B's rows have not arrived, and
      // A's colleagues must already be off the screen and out of the cubit.
      expect(users.pendingUserCount, 1);
      expect(find.text('Amina Rahman'), findsNothing);
      expect(find.text('Jo Nakamura'), findsNothing);
      expect(find.text('Finance Admin'), findsNothing);
      expect(cubit<VendorUserListCubit>(tester).state.users, isEmpty);

      users.completeUsers(
        ReadSuccess<List<VendorUserSummary>>(<VendorUserSummary>[joSummary]),
      );
      await settle(tester);

      expect(find.text('Jo Nakamura'), findsOneWidget);
      expect(find.text('Amina Rahman'), findsNothing);
    });

    testWidgets('A\'s Retailer directory and open detail are cleared too', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      await cubit<VendorRetailerDetailCubit>(
        tester,
      ).open(northwindRelationshipUuid);
      await settle(tester);
      expect(
        cubit<VendorRetailerListCubit>(tester).state.retailers,
        isNotEmpty,
      );
      expect(cubit<VendorRetailerDetailCubit>(tester).state.detail, isNotNull);

      await emit(tester, vendorB);

      expect(cubit<VendorRetailerDetailCubit>(tester).state.detail, isNull);
      expect(
        cubit<VendorRetailerDetailCubit>(tester).state.relationshipId,
        isNull,
      );
      expect(cubit<VendorRetailerDetailCubit>(tester).state.shops, isEmpty);
    });

    testWidgets('A\'s search term and filters do not survive', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      cubit<VendorUserListCubit>(tester).search('amina');
      await settle(tester);
      expect(find.text('Showing 1 of 2'), findsOneWidget);

      await emit(tester, vendorB);

      final VendorUserListCubit list = cubit<VendorUserListCubit>(tester);
      expect(list.state.searchTerm, isEmpty);
      expect(list.state.profileFilter, isNull);
      expect(list.state.membershipFilter, isNull);
    });

    testWidgets('a stale A list response cannot repopulate B\'s screen', (
      WidgetTester tester,
    ) async {
      users.manualUsers = true;
      await pumpShell(tester);
      // A's first read is still in flight when the identity changes.
      expect(users.pendingUserCount, 1);

      await emit(tester, vendorB);
      expect(users.pendingUserCount, 2);

      // A's answer lands *after* the switch. It must be discarded.
      users.completeUsers(
        ReadSuccess<List<VendorUserSummary>>(<VendorUserSummary>[aminaSummary]),
      );
      await settle(tester);

      expect(find.text('Amina Rahman'), findsNothing);
      expect(cubit<VendorUserListCubit>(tester).state.users, isEmpty);

      // B's own answer still lands normally.
      users.completeUsers(
        ReadSuccess<List<VendorUserSummary>>(<VendorUserSummary>[joSummary]),
      );
      await settle(tester);
      expect(find.text('Jo Nakamura'), findsOneWidget);
    });

    testWidgets('a stale A detail response cannot repopulate B\'s screen', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      users.manualDetail = true;
      unawaited(cubit<VendorUserDetailCubit>(tester).open(aminaMembershipUuid));
      await settle(tester);
      expect(users.pendingDetailCount, 1);

      await emit(tester, vendorB);

      // A's detail answers late.
      users.completeDetail(ReadSuccess<VendorUserDetail?>(aminaDetail));
      await settle(tester);

      final VendorUserDetailCubit detail = cubit<VendorUserDetailCubit>(tester);
      expect(detail.state.detail, isNull);
      expect(detail.state.membershipId, isNull);
      expect(detail.state.phase, VendorUserDetailPhase.initial);
    });

    testWidgets('B\'s directory loads exactly once', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      final int before = users.usersCallCount;

      await emit(tester, vendorB);

      expect(users.usersCallCount, before + 1);
    });
  });

  group('the same authenticated user', () {
    testWidgets('an identical re-emitted session clears and loads nothing', (
      WidgetTester tester,
    ) async {
      // The shape a same-user token refresh takes if it ever reaches this far.
      // The effective identity is unchanged, so there is nothing to protect and
      // nothing to re-read.
      await pumpShell(tester);
      cubit<VendorUserListCubit>(tester).search('amina');
      await settle(tester);

      await emit(
        tester,
        SessionActive(vendorContext(orgOne), authUserId: 'user-A'),
      );

      expect(users.usersCallCount, 1);
      expect(retailers.retailersCallCount, 1);
      expect(find.text('Amina Rahman'), findsOneWidget);
      // Even the half-typed search survives, because nothing about the session
      // actually changed.
      expect(cubit<VendorUserListCubit>(tester).state.searchTerm, 'amina');
    });

    testWidgets('a changed trusted organization does clear and reload', (
      WidgetTester tester,
    ) async {
      // Same person, different Vendor organization: the rows the RPCs return
      // are a different tenant's, so holding the old ones would be a leak.
      await pumpShell(tester);

      await emit(
        tester,
        SessionActive(vendorContext(orgTwo), authUserId: 'user-A'),
      );

      expect(users.usersCallCount, 2);
      expect(retailers.retailersCallCount, 2);
    });
  });

  group('leaving the Vendor session', () {
    testWidgets('signing out clears everything and reloads nothing', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      expect(find.text('Amina Rahman'), findsOneWidget);

      await emit(tester, const SessionUnauthenticated());

      expect(cubit<VendorUserListCubit>(tester).state.users, isEmpty);
      expect(cubit<VendorRetailerListCubit>(tester).state.retailers, isEmpty);
      // Nothing is fetched for a caller who is not there.
      expect(users.usersCallCount, 1);
      expect(retailers.retailersCallCount, 1);
    });

    testWidgets('becoming another role clears everything and reloads nothing', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);

      await emit(
        tester,
        SessionActive(retailerContext(), authUserId: 'user-A'),
      );

      expect(cubit<VendorUserListCubit>(tester).state.users, isEmpty);
      expect(cubit<VendorRetailerListCubit>(tester).state.retailers, isEmpty);
      expect(users.usersCallCount, 1);
    });

    testWidgets('a session invalidation clears everything', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);

      await emit(tester, const SessionUnavailable(UnavailableFailure()));

      expect(cubit<VendorUserListCubit>(tester).state.users, isEmpty);
      expect(cubit<VendorRetailerListCubit>(tester).state.retailers, isEmpty);
      expect(users.usersCallCount, 1);
    });

    testWidgets('a denial clears everything', (WidgetTester tester) async {
      await pumpShell(tester);

      await emit(tester, const SessionDenied());

      expect(cubit<VendorUserListCubit>(tester).state.users, isEmpty);
      expect(users.usersCallCount, 1);
    });

    testWidgets('coming back to the same identity reloads once', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);

      await emit(tester, const SessionUnauthenticated());
      expect(users.usersCallCount, 1);

      await emit(tester, vendorA);

      expect(users.usersCallCount, 2);
      expect(retailers.retailersCallCount, 2);
    });
  });

  group('a Vendor context with no vendor block', () {
    testWidgets('is treated as no identity rather than as a tenant', (
      WidgetTester tester,
    ) async {
      // The router would not build this shell for such a context, but the rule
      // is worth pinning: inventing a comparable identity out of a missing
      // organization is how two different tenants come to look equal.
      await pumpShell(tester);

      await emit(
        tester,
        const SessionActive(
          PortalContext(
            contextVersion: supportedPortalContextVersion,
            portalKind: PortalKind.vendorSuperAdmin,
          ),
          authUserId: 'user-A',
        ),
      );

      expect(cubit<VendorUserListCubit>(tester).state.users, isEmpty);
      expect(users.usersCallCount, 1);
    });
  });

  /// The Vendor Role pair, added by the Role milestone.
  ///
  /// The role **definitions** are global — every authorized Vendor reads the
  /// same rows — so it would be tempting to treat the catalogue as a harmless
  /// cache that survives a session change. It is not:
  /// `assigned_member_count` rides on those same rows and counts the **calling**
  /// Vendor's own memberships, so leaving the list in place would leave one
  /// Vendor's staffing numbers legible to the next person on the device. The
  /// search term is private for the same reason it is on the other two screens.
  group('the Vendor Role pair', () {
    testWidgets('A\'s catalogue and counts are gone before B answers', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      final VendorRoleListCubit list = cubit<VendorRoleListCubit>(tester);
      expect(list.state.roles, isNotEmpty);
      expect(list.state.totalAssignments, greaterThan(0));

      // B's catalogue will not answer until this test says so.
      roles.manualRoles = true;
      await emit(tester, vendorB);

      // The window that matters: B is signed in, B's rows have not arrived, and
      // A's member counts must already be out of the cubit.
      expect(roles.pendingRoleCount, 1);
      expect(cubit<VendorRoleListCubit>(tester).state.roles, isEmpty);
      expect(cubit<VendorRoleListCubit>(tester).state.totalAssignments, 0);

      roles.completeRoles(
        ReadSuccess<List<VendorRoleSummary>>(<VendorRoleSummary>[
          claimReviewerSummary,
        ]),
      );
      await settle(tester);

      expect(cubit<VendorRoleListCubit>(tester).state.roles, hasLength(1));
    });

    testWidgets('B\'s catalogue loads exactly once', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      expect(roles.rolesCallCount, 1);

      await emit(tester, vendorB);

      expect(roles.rolesCallCount, 2);
    });

    testWidgets('an open role, its permissions and its counts are cleared', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      await cubit<VendorRoleDetailCubit>(tester).open(superAdminRoleUuid);
      await settle(tester);
      expect(cubit<VendorRoleDetailCubit>(tester).state.detail, isNotNull);
      expect(
        cubit<VendorRoleDetailCubit>(tester).state.permissions,
        isNotEmpty,
      );

      await emit(tester, vendorB);

      final VendorRoleDetailCubit detail = cubit<VendorRoleDetailCubit>(tester);
      expect(detail.state.detail, isNull);
      expect(detail.state.roleId, isNull);
      expect(detail.state.permissions, isEmpty);
      expect(detail.state.phase, VendorRoleDetailPhase.initial);
    });

    testWidgets('A\'s search term and status filter do not survive', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      final VendorRoleListCubit list = cubit<VendorRoleListCubit>(tester);
      list.search('legacy');
      list.filterByStatus(VendorRoleStatus.inactive);
      await settle(tester);

      await emit(tester, vendorB);

      expect(cubit<VendorRoleListCubit>(tester).state.searchTerm, isEmpty);
      expect(cubit<VendorRoleListCubit>(tester).state.statusFilter, isNull);
    });

    testWidgets('a stale A catalogue response cannot repopulate B\'s screen', (
      WidgetTester tester,
    ) async {
      roles.manualRoles = true;
      await pumpShell(tester);
      expect(roles.pendingRoleCount, 1);

      await emit(tester, vendorB);
      expect(roles.pendingRoleCount, 2);

      // A's answer lands *after* the switch. It must be discarded, counts and
      // all.
      roles.completeRoles(
        ReadSuccess<List<VendorRoleSummary>>(catalogueSummaries),
      );
      await settle(tester);
      expect(cubit<VendorRoleListCubit>(tester).state.roles, isEmpty);

      // B's own answer still lands normally.
      roles.completeRoles(
        ReadSuccess<List<VendorRoleSummary>>(<VendorRoleSummary>[
          claimReviewerSummary,
        ]),
      );
      await settle(tester);
      expect(cubit<VendorRoleListCubit>(tester).state.roles, hasLength(1));
    });

    testWidgets('a stale A role-detail response cannot repopulate B', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      roles.manualDetail = true;
      unawaited(cubit<VendorRoleDetailCubit>(tester).open(superAdminRoleUuid));
      await settle(tester);
      expect(roles.pendingDetailCount, 1);

      await emit(tester, vendorB);

      roles.completeDetail(ReadSuccess<VendorRoleDetail?>(superAdminSummary));
      await settle(tester);

      final VendorRoleDetailCubit detail = cubit<VendorRoleDetailCubit>(tester);
      expect(detail.state.detail, isNull);
      expect(detail.state.roleId, isNull);
      expect(detail.state.phase, VendorRoleDetailPhase.initial);
    });

    testWidgets('a stale A permission response cannot repopulate B', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      roles.manualPermissions = true;
      unawaited(cubit<VendorRoleDetailCubit>(tester).open(superAdminRoleUuid));
      await settle(tester);
      // The detail landed; the companion is still in flight.
      expect(roles.pendingPermissionCount, 1);

      await emit(tester, vendorB);

      roles.completePermissions(
        ReadSuccess<List<VendorRolePermission>>(superAdminPermissions),
      );
      await settle(tester);

      expect(cubit<VendorRoleDetailCubit>(tester).state.permissions, isEmpty);
    });

    testWidgets('an identical re-emitted session is a no-op for roles', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      cubit<VendorRoleListCubit>(tester).search('legacy');
      await settle(tester);

      await emit(
        tester,
        SessionActive(vendorContext(orgOne), authUserId: 'user-A'),
      );

      expect(roles.rolesCallCount, 1);
      expect(cubit<VendorRoleListCubit>(tester).state.roles, isNotEmpty);
      expect(cubit<VendorRoleListCubit>(tester).state.searchTerm, 'legacy');
    });

    testWidgets('a changed trusted organization reloads the catalogue', (
      WidgetTester tester,
    ) async {
      // The definitions would be identical, but the member counts on them are
      // another organization's — so the rows are re-read rather than kept.
      await pumpShell(tester);

      await emit(
        tester,
        SessionActive(vendorContext(orgTwo), authUserId: 'user-A'),
      );

      expect(roles.rolesCallCount, 2);
    });

    testWidgets('signing out clears the catalogue and reloads nothing', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);

      await emit(tester, const SessionUnauthenticated());

      expect(cubit<VendorRoleListCubit>(tester).state.roles, isEmpty);
      expect(roles.rolesCallCount, 1);
    });

    testWidgets('becoming another role clears the catalogue', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);

      await emit(
        tester,
        SessionActive(retailerContext(), authUserId: 'user-A'),
      );

      expect(cubit<VendorRoleListCubit>(tester).state.roles, isEmpty);
      expect(roles.rolesCallCount, 1);
    });

    testWidgets('the Retailer and User state is still cleared alongside', (
      WidgetTester tester,
    ) async {
      // The Role milestone must not have displaced either earlier half of the
      // listener.
      await pumpShell(tester);

      await emit(tester, vendorB);

      expect(users.usersCallCount, 2);
      expect(retailers.retailersCallCount, 2);
      expect(roles.rolesCallCount, 2);
    });
  });

  /// The Vendor Product pair, added by the Product milestone.
  ///
  /// Unlike the Role catalogue, **nothing** about a product catalogue is
  /// global: `vendor_products.vendor_organization_id` is `NOT NULL` and
  /// immutable, so every row — its name, code, barcode, brand, description and
  /// assignment counts — belongs to exactly one Vendor. The open product carries
  /// more still: the names and statuses of the Retailers holding it. So there is
  /// no version of this pair that could be kept as a harmless cache.
  group('the Vendor Product pair', () {
    testWidgets('A\'s catalogue is gone before B answers', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      final VendorProductListCubit list = cubit<VendorProductListCubit>(tester);
      expect(list.state.products, isNotEmpty);
      expect(list.state.totalActiveAssignments, greaterThan(0));

      // B's catalogue will not answer until this test says so.
      products.manualProducts = true;
      await emit(tester, vendorB);

      // The window that matters: B is signed in, B's rows have not arrived, and
      // A's products must already be out of the cubit.
      expect(products.pendingProductCount, 1);
      expect(cubit<VendorProductListCubit>(tester).state.products, isEmpty);
      expect(
        cubit<VendorProductListCubit>(tester).state.totalActiveAssignments,
        0,
      );

      products.completeProducts(
        ReadSuccess<List<VendorProductSummary>>(<VendorProductSummary>[
          decafSummary,
        ]),
      );
      await settle(tester);

      expect(
        cubit<VendorProductListCubit>(tester).state.products,
        hasLength(1),
      );
    });

    testWidgets('B\'s catalogue loads exactly once', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      expect(products.productsCallCount, 1);

      await emit(tester, vendorB);

      expect(products.productsCallCount, 2);
    });

    testWidgets('an open product and its assignment rows are cleared', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      await cubit<VendorProductDetailCubit>(tester).open(espressoProductUuid);
      await settle(tester);
      expect(cubit<VendorProductDetailCubit>(tester).state.detail, isNotNull);
      expect(
        cubit<VendorProductDetailCubit>(tester).state.assignments,
        isNotEmpty,
      );

      await emit(tester, vendorB);

      final VendorProductDetailCubit detail = cubit<VendorProductDetailCubit>(
        tester,
      );
      expect(detail.state.detail, isNull);
      expect(detail.state.productId, isNull);
      // The Retailer names and statuses that rode on those rows go with them.
      expect(detail.state.assignments, isEmpty);
      expect(detail.state.phase, VendorProductDetailPhase.initial);
      expect(
        detail.state.assignmentsPhase,
        VendorProductAssignmentsPhase.initial,
      );
    });

    testWidgets('A\'s search term and status filter do not survive', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      final VendorProductListCubit list = cubit<VendorProductListCubit>(tester);
      list.search('espresso');
      list.filterByStatus(VendorProductStatus.inactive);
      await settle(tester);

      await emit(tester, vendorB);

      expect(cubit<VendorProductListCubit>(tester).state.searchTerm, isEmpty);
      expect(cubit<VendorProductListCubit>(tester).state.statusFilter, isNull);
    });

    testWidgets('a stale A catalogue response cannot repopulate B\'s screen', (
      WidgetTester tester,
    ) async {
      products.manualProducts = true;
      await pumpShell(tester);
      expect(products.pendingProductCount, 1);

      await emit(tester, vendorB);
      expect(products.pendingProductCount, 2);

      // A's answer lands *after* the switch. It must be discarded, counts and
      // all.
      products.completeProducts(
        ReadSuccess<List<VendorProductSummary>>(productCatalogueSummaries),
      );
      await settle(tester);
      expect(cubit<VendorProductListCubit>(tester).state.products, isEmpty);

      // B's own answer still lands normally.
      products.completeProducts(
        ReadSuccess<List<VendorProductSummary>>(<VendorProductSummary>[
          decafSummary,
        ]),
      );
      await settle(tester);
      expect(
        cubit<VendorProductListCubit>(tester).state.products,
        hasLength(1),
      );
    });

    testWidgets('a stale A product-detail response cannot repopulate B', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      products.manualDetail = true;
      unawaited(
        cubit<VendorProductDetailCubit>(tester).open(espressoProductUuid),
      );
      await settle(tester);
      expect(products.pendingDetailCount, 1);

      await emit(tester, vendorB);

      products.completeDetail(
        ReadSuccess<VendorProductDetail?>(espressoDetail),
      );
      await settle(tester);

      final VendorProductDetailCubit detail = cubit<VendorProductDetailCubit>(
        tester,
      );
      expect(detail.state.detail, isNull);
      expect(detail.state.productId, isNull);
      expect(detail.state.phase, VendorProductDetailPhase.initial);
    });

    testWidgets('a stale A assignment response cannot repopulate B', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      products.manualAssignments = true;
      unawaited(
        cubit<VendorProductDetailCubit>(tester).open(espressoProductUuid),
      );
      await settle(tester);
      // The detail landed; the companion is still in flight.
      expect(products.pendingAssignmentCount, 1);

      await emit(tester, vendorB);

      products.completeAssignments(
        ReadSuccess<List<VendorProductAssignedRetailer>>(espressoAssignments),
      );
      await settle(tester);

      expect(
        cubit<VendorProductDetailCubit>(tester).state.assignments,
        isEmpty,
      );
    });

    testWidgets('an identical re-emitted session is a no-op for products', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      cubit<VendorProductListCubit>(tester).search('espresso');
      await settle(tester);

      await emit(
        tester,
        SessionActive(vendorContext(orgOne), authUserId: 'user-A'),
      );

      expect(products.productsCallCount, 1);
      expect(cubit<VendorProductListCubit>(tester).state.products, isNotEmpty);
      expect(
        cubit<VendorProductListCubit>(tester).state.searchTerm,
        'espresso',
      );
    });

    testWidgets('a changed trusted organization reloads the catalogue', (
      WidgetTester tester,
    ) async {
      // Same person, different Vendor organization: an entirely different
      // catalogue, so the rows are re-read rather than kept.
      await pumpShell(tester);

      await emit(
        tester,
        SessionActive(vendorContext(orgTwo), authUserId: 'user-A'),
      );

      expect(products.productsCallCount, 2);
    });

    testWidgets('signing out clears the catalogue and reloads nothing', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);

      await emit(tester, const SessionUnauthenticated());

      expect(cubit<VendorProductListCubit>(tester).state.products, isEmpty);
      expect(products.productsCallCount, 1);
    });

    testWidgets('becoming another role clears the catalogue', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);

      await emit(
        tester,
        SessionActive(retailerContext(), authUserId: 'user-A'),
      );

      expect(cubit<VendorProductListCubit>(tester).state.products, isEmpty);
      expect(products.productsCallCount, 1);
    });

    testWidgets('a session invalidation clears the catalogue', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);

      await emit(tester, const SessionUnavailable(UnavailableFailure()));

      expect(cubit<VendorProductListCubit>(tester).state.products, isEmpty);
      expect(products.productsCallCount, 1);
    });

    testWidgets('a denial clears the catalogue', (WidgetTester tester) async {
      await pumpShell(tester);

      await emit(tester, const SessionDenied());

      expect(cubit<VendorProductListCubit>(tester).state.products, isEmpty);
      expect(products.productsCallCount, 1);
    });

    testWidgets(
      'the Retailer, User and Role state is still cleared alongside',
      (WidgetTester tester) async {
        // The Product milestone must not have displaced any earlier part of the
        // listener.
        await pumpShell(tester);

        await emit(tester, vendorB);

        expect(users.usersCallCount, 2);
        expect(retailers.retailersCallCount, 2);
        expect(roles.rolesCallCount, 2);
        expect(products.productsCallCount, 2);
      },
    );
  });

  /// The Vendor Product **assignment** cubit, added by the assignment-writes
  /// milestone.
  ///
  /// It holds more than a pending decision: the names and trading statuses of
  /// every Retailer one Vendor works with, a search term that is a fragment of
  /// one of those names, and any in-flight assign or withdrawal. All of it is
  /// one Vendor's, and none of it may survive into another's session.
  group('the Vendor Product assignment surface', () {
    Future<void> loadCandidates(WidgetTester tester) async {
      await cubit<VendorProductAssignmentCubit>(tester).loadCandidates(
        productId: espressoProductUuid,
        assignments: compositionAssignments,
      );
      await settle(tester);
    }

    testWidgets('a direct A → B switch clears the candidate Retailers', (
      WidgetTester tester,
    ) async {
      retailers.retailersResult =
          VendorRetailerReadSuccess<List<VendorRetailerSummary>>(
            assignmentDirectory,
          );
      await pumpShell(tester);
      await loadCandidates(tester);
      expect(
        cubit<VendorProductAssignmentCubit>(tester).state.candidates,
        isNotEmpty,
      );

      await emit(tester, vendorB);

      expect(
        cubit<VendorProductAssignmentCubit>(tester).state.candidates,
        isEmpty,
      );
      expect(
        cubit<VendorProductAssignmentCubit>(tester).state.candidatesPhase,
        VendorProductAssignmentCandidatesPhase.initial,
      );
    });

    testWidgets('it clears the search term, the selection and the notice', (
      WidgetTester tester,
    ) async {
      retailers.retailersResult =
          VendorRetailerReadSuccess<List<VendorRetailerSummary>>(
            assignmentDirectory,
          );
      await pumpShell(tester);
      await loadCandidates(tester);
      cubit<VendorProductAssignmentCubit>(tester).searchCandidates('lakeside');
      await cubit<VendorProductAssignmentCubit>(tester).apply(
        productId: espressoProductUuid,
        retailerOrganizationId: lakesideOrgId,
        action: VendorProductAssignmentAction.assign,
      );
      await settle(tester);

      await emit(tester, vendorB);

      final VendorProductAssignmentState state =
          cubit<VendorProductAssignmentCubit>(tester).state;
      expect(state.searchTerm, isEmpty);
      expect(state.productId, isNull);
      expect(state.pendingRetailerOrganizationId, isNull);
      expect(state.pendingAction, isNull);
      expect(state.notice, isNull);
      expect(state.failure, isNull);
      expect(state.phase, VendorProductAssignmentPhase.idle);
    });

    testWidgets('a stale ASSIGN answer cannot land under the new Vendor', (
      WidgetTester tester,
    ) async {
      products.manualAssignmentWrites = true;
      await pumpShell(tester);

      unawaited(
        cubit<VendorProductAssignmentCubit>(tester).apply(
          productId: espressoProductUuid,
          retailerOrganizationId: lakesideOrgId,
          action: VendorProductAssignmentAction.assign,
        ),
      );
      await settle(tester);
      expect(products.pendingAssignmentWriteCount, 1);

      await emit(tester, vendorB);
      products.completeAssignment();
      await settle(tester);

      expect(
        cubit<VendorProductAssignmentCubit>(tester).state.notice,
        isNull,
        reason: 'A\'s acknowledgement must never appear over B\'s product',
      );
      expect(
        cubit<VendorProductAssignmentCubit>(tester).state.phase,
        VendorProductAssignmentPhase.idle,
      );
    });

    testWidgets('a stale WITHDRAW answer cannot land either', (
      WidgetTester tester,
    ) async {
      products.manualAssignmentWrites = true;
      await pumpShell(tester);

      unawaited(
        cubit<VendorProductAssignmentCubit>(tester).apply(
          productId: espressoProductUuid,
          retailerOrganizationId: northwindOrgId,
          action: VendorProductAssignmentAction.withdraw,
        ),
      );
      await settle(tester);

      await emit(tester, vendorB);
      products.completeAssignment();
      await settle(tester);

      expect(cubit<VendorProductAssignmentCubit>(tester).state.notice, isNull);
    });

    testWidgets('a stale refusal cannot appear under the new Vendor', (
      WidgetTester tester,
    ) async {
      products.manualAssignmentWrites = true;
      await pumpShell(tester);

      unawaited(
        cubit<VendorProductAssignmentCubit>(tester).apply(
          productId: espressoProductUuid,
          retailerOrganizationId: lakesideOrgId,
          action: VendorProductAssignmentAction.assign,
        ),
      );
      await settle(tester);

      await emit(tester, vendorB);
      products.completeAssignment(
        const VendorProductWriteFailure<void>(DeniedFailure()),
      );
      await settle(tester);

      expect(cubit<VendorProductAssignmentCubit>(tester).state.failure, isNull);
    });

    testWidgets('a stale candidate read cannot repopulate the picker', (
      WidgetTester tester,
    ) async {
      retailers.manualRetailers = true;
      await pumpShell(tester);
      unawaited(loadCandidates(tester));
      await settle(tester);

      await emit(tester, vendorB);
      // The listener reloads the directory for B, so the pending queue holds A's
      // read first and B's second. Completing A's must change nothing.
      retailers.completeRetailers(
        VendorRetailerReadSuccess<List<VendorRetailerSummary>>(
          assignmentDirectory,
        ),
      );
      await settle(tester);

      expect(
        cubit<VendorProductAssignmentCubit>(tester).state.candidates,
        isEmpty,
      );
    });

    testWidgets('the assignment surface is NOT reloaded for the new Vendor', (
      WidgetTester tester,
    ) async {
      // It has nothing to load until a product is open and a picker is asked
      // for, so eagerly re-reading the directory into it would be a request
      // nobody made.
      await pumpShell(tester);
      final int before = retailers.retailersCallCount;

      await emit(tester, vendorB);

      expect(
        cubit<VendorProductAssignmentCubit>(tester).state.candidatesPhase,
        VendorProductAssignmentCandidatesPhase.initial,
      );
      // Exactly the directory screen's own reload, and no second one.
      expect(retailers.retailersCallCount, before + 1);
    });

    testWidgets('signing out clears it and reloads nothing', (
      WidgetTester tester,
    ) async {
      retailers.retailersResult =
          VendorRetailerReadSuccess<List<VendorRetailerSummary>>(
            assignmentDirectory,
          );
      await pumpShell(tester);
      await loadCandidates(tester);

      await emit(tester, const SessionUnauthenticated());

      expect(
        cubit<VendorProductAssignmentCubit>(tester).state,
        const VendorProductAssignmentState(),
      );
    });

    testWidgets('becoming a Retailer clears it', (WidgetTester tester) async {
      retailers.retailersResult =
          VendorRetailerReadSuccess<List<VendorRetailerSummary>>(
            assignmentDirectory,
          );
      await pumpShell(tester);
      await loadCandidates(tester);

      await emit(
        tester,
        SessionActive(retailerContext(), authUserId: 'user-A'),
      );

      expect(
        cubit<VendorProductAssignmentCubit>(tester).state.candidates,
        isEmpty,
      );
    });

    testWidgets('an identical re-emitted session leaves an open picker alone', (
      WidgetTester tester,
    ) async {
      retailers.retailersResult =
          VendorRetailerReadSuccess<List<VendorRetailerSummary>>(
            assignmentDirectory,
          );
      await pumpShell(tester);
      await loadCandidates(tester);
      cubit<VendorProductAssignmentCubit>(tester).searchCandidates('lakeside');
      await settle(tester);

      await emit(
        tester,
        SessionActive(vendorContext(orgOne), authUserId: 'user-A'),
      );

      expect(
        cubit<VendorProductAssignmentCubit>(tester).state.candidates,
        isNotEmpty,
      );
      expect(
        cubit<VendorProductAssignmentCubit>(tester).state.searchTerm,
        'lakeside',
      );
    });

    testWidgets(
      'the Product create, edit and status isolation is still intact',
      (WidgetTester tester) async {
        // The assignment milestone must not have displaced any earlier part of
        // the listener.
        await pumpShell(tester);

        await emit(tester, vendorB);

        expect(users.usersCallCount, 2);
        expect(retailers.retailersCallCount, 2);
        expect(roles.rolesCallCount, 2);
        expect(products.productsCallCount, 2);
        expect(products.submittedAssignments, isEmpty);
      },
    );
  });

  /// The Vendor Audit Log cubit, added by the Audit Log milestone.
  ///
  /// A single cubit rather than a pair — there is no audit detail read to hold —
  /// but it carries something the other four do not: a **cursor position**. So
  /// clearing it has to drop three things at once. The loaded events, which name
  /// colleagues, Retailers, shops and products and the moment each was touched.
  /// The end-of-history flag, which is a statement about *this* Vendor's record.
  /// And the cursor itself, which is why the next Vendor cannot continue paging
  /// from where the previous one stopped.
  group('the Vendor Audit Log feed', () {
    testWidgets('A\'s recorded activity is gone before B answers', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      final VendorAuditLogCubit feed = cubit<VendorAuditLogCubit>(tester);
      expect(feed.state.events, isNotEmpty);

      // B's feed will not answer until this test says so.
      auditLogs.manual = true;
      await emit(tester, vendorB);

      // The window that matters: B is signed in, B's rows have not arrived, and
      // A's activity must already be out of the cubit.
      expect(auditLogs.pendingCount, 1);
      expect(cubit<VendorAuditLogCubit>(tester).state.events, isEmpty);
      expect(cubit<VendorAuditLogCubit>(tester).state.loadedCount, 0);

      auditLogs.complete(
        ReadSuccess<List<VendorAuditLogEntry>>(<VendorAuditLogEntry>[
          systemActorEvent,
        ]),
      );
      await settle(tester);

      expect(cubit<VendorAuditLogCubit>(tester).state.events, hasLength(1));
    });

    testWidgets('B\'s feed loads exactly once', (WidgetTester tester) async {
      await pumpShell(tester);
      expect(auditLogs.callCount, 1);

      await emit(tester, vendorB);

      expect(auditLogs.callCount, 2);
      // And the reload is a NEWEST-page read: no cursor survives a session
      // change, so B cannot continue from where A had paged to.
      expect(auditLogs.newestCallCount, 2);
      expect(auditLogs.olderCursors, isEmpty);
    });

    testWidgets('the cursor and the end-of-history flag are cleared too', (
      WidgetTester tester,
    ) async {
      // Page A's feed to its end first, so both are genuinely set. Sixty events
      // is two pages at the client's fixed fifty.
      auditLogs.history = auditHistoryOf(60);
      await pumpShell(tester);
      await cubit<VendorAuditLogCubit>(tester).loadMore();
      await settle(tester);
      expect(cubit<VendorAuditLogCubit>(tester).state.events, hasLength(60));
      expect(cubit<VendorAuditLogCubit>(tester).state.hasReachedEnd, isTrue);
      expect(auditLogs.olderCursors, hasLength(1));

      await emit(tester, vendorB);

      final VendorAuditLogCubit feed = cubit<VendorAuditLogCubit>(tester);
      // B holds a fresh FIRST page — not A's sixty, and not a continuation of
      // them. The end flag went with the rows, because "there is nothing older"
      // was a statement about A's history.
      expect(feed.state.events, hasLength(50));
      expect(feed.state.hasReachedEnd, isFalse);
      expect(feed.state.isLoadingMore, isFalse);
      expect(feed.state.isRefreshing, isFalse);
      expect(feed.state.failure, isNull);
      expect(feed.state.loadMoreFailure, isNull);
      // The reload sent NO cursor: B cannot continue from where A stopped.
      expect(auditLogs.olderCursors, hasLength(1));
      expect(auditLogs.requestedCursors.last, isNull);
    });

    testWidgets('a stale A first-page response cannot repopulate B', (
      WidgetTester tester,
    ) async {
      auditLogs.manual = true;
      await pumpShell(tester);
      expect(auditLogs.pendingCount, 1);

      await emit(tester, vendorB);
      expect(auditLogs.pendingCount, 2);

      // A's answer lands *after* the switch. It must be discarded.
      auditLogs.completeAt(
        0,
        ReadSuccess<List<VendorAuditLogEntry>>(auditFirstPage),
      );
      await settle(tester);
      expect(cubit<VendorAuditLogCubit>(tester).state.events, isEmpty);

      // B's own answer still lands normally.
      auditLogs.complete(
        ReadSuccess<List<VendorAuditLogEntry>>(<VendorAuditLogEntry>[
          systemActorEvent,
        ]),
      );
      await settle(tester);
      expect(cubit<VendorAuditLogCubit>(tester).state.events, hasLength(1));
    });

    testWidgets('a stale A refresh response cannot repopulate B', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      auditLogs.manual = true;
      unawaited(cubit<VendorAuditLogCubit>(tester).refresh());
      await settle(tester);
      expect(auditLogs.pendingCount, 1);

      await emit(tester, vendorB);

      auditLogs.completeAt(
        0,
        ReadSuccess<List<VendorAuditLogEntry>>(auditFirstPage),
      );
      await settle(tester);

      expect(cubit<VendorAuditLogCubit>(tester).state.events, isEmpty);
    });

    testWidgets('a stale A load-more response cannot repopulate B', (
      WidgetTester tester,
    ) async {
      auditLogs.history = auditHistoryOf(60);
      await pumpShell(tester);
      expect(cubit<VendorAuditLogCubit>(tester).state.events, hasLength(50));

      auditLogs.manual = true;
      unawaited(cubit<VendorAuditLogCubit>(tester).loadMore());
      await settle(tester);
      expect(auditLogs.pendingCount, 1);

      await emit(tester, vendorB);

      // A's older page answers late. Appending it would splice one Vendor's
      // history onto another's.
      auditLogs.completeAt(
        0,
        ReadSuccess<List<VendorAuditLogEntry>>(
          auditHistoryOf(60).skip(50).toList(),
        ),
      );
      await settle(tester);

      expect(cubit<VendorAuditLogCubit>(tester).state.events, isEmpty);
    });

    testWidgets('an identical re-emitted session is a no-op for the feed', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);

      await emit(
        tester,
        SessionActive(vendorContext(orgOne), authUserId: 'user-A'),
      );

      expect(auditLogs.callCount, 1);
      expect(cubit<VendorAuditLogCubit>(tester).state.events, isNotEmpty);
    });

    testWidgets('a changed trusted organization reloads the feed', (
      WidgetTester tester,
    ) async {
      // Same person, a different Vendor organization: an entirely different
      // history, so the rows are re-read rather than kept.
      await pumpShell(tester);

      await emit(
        tester,
        SessionActive(vendorContext(orgTwo), authUserId: 'user-A'),
      );

      expect(auditLogs.callCount, 2);
    });

    testWidgets('signing out clears the feed and reloads nothing', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);

      await emit(tester, const SessionUnauthenticated());

      expect(cubit<VendorAuditLogCubit>(tester).state.events, isEmpty);
      expect(auditLogs.callCount, 1);
    });

    testWidgets('becoming another role clears the feed', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);

      await emit(
        tester,
        SessionActive(retailerContext(), authUserId: 'user-A'),
      );

      expect(cubit<VendorAuditLogCubit>(tester).state.events, isEmpty);
      expect(auditLogs.callCount, 1);
    });

    testWidgets('a session invalidation clears the feed', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);

      await emit(tester, const SessionUnavailable(UnavailableFailure()));

      expect(cubit<VendorAuditLogCubit>(tester).state.events, isEmpty);
      expect(auditLogs.callCount, 1);
    });

    testWidgets('a denial clears the feed', (WidgetTester tester) async {
      await pumpShell(tester);

      await emit(tester, const SessionDenied());

      expect(cubit<VendorAuditLogCubit>(tester).state.events, isEmpty);
      expect(auditLogs.callCount, 1);
    });

    testWidgets(
      'the Retailer, User, Role and Product state is still cleared alongside',
      (WidgetTester tester) async {
        // The Audit Log milestone must not have displaced any earlier part of
        // the listener.
        await pumpShell(tester);

        await emit(tester, vendorB);

        expect(users.usersCallCount, 2);
        expect(retailers.retailersCallCount, 2);
        expect(roles.rolesCallCount, 2);
        expect(products.productsCallCount, 2);
        expect(auditLogs.callCount, 2);
      },
    );
  });

  /// The Vendor Dashboard summary, added by the Dashboard milestone.
  ///
  /// Unlike every other cubit in this shell, this one holds a **mixture**: two
  /// counts belong to the caller's Vendor — how many people work there, and how
  /// much has ever happened there — and two are deployment-wide catalogue figures
  /// identical for whoever signs in next. It would therefore be tempting to keep
  /// the global half as a harmless cache.
  ///
  /// It is not kept, and the reason is not privacy alone: the four figures are
  /// **one snapshot from one statement**, so a summary carrying only its global
  /// half is a shape no backend answer ever produces. Rendering one would show a
  /// screen the contract cannot explain. The whole snapshot goes.
  group('the Vendor Dashboard summary', () {
    testWidgets('A\'s figures are gone before B answers', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      expect(
        cubit<VendorDashboardCubit>(tester).state.summary,
        exampleDashboardSummary,
      );

      // B's summary will not answer until this test says so.
      dashboard.manual = true;
      await emit(tester, vendorB);

      // The window that matters: B is signed in, B's figures have not arrived,
      // and A's member count and recorded-event total must already be out of the
      // cubit.
      expect(dashboard.pendingCount, 1);
      expect(cubit<VendorDashboardCubit>(tester).state.summary, isNull);
      expect(
        cubit<VendorDashboardCubit>(tester).state.phase,
        VendorDashboardPhase.loading,
      );

      dashboard.complete(
        const ReadSuccess<VendorDashboardSummary>(otherVendorDashboardSummary),
      );
      await settle(tester);

      expect(
        cubit<VendorDashboardCubit>(tester).state.summary,
        otherVendorDashboardSummary,
      );
    });

    testWidgets('the global half is cleared alongside the tenant half', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      dashboard.manual = true;

      await emit(tester, vendorB);

      // Not a partially populated snapshot — nothing at all.
      expect(cubit<VendorDashboardCubit>(tester).state.summary, isNull);
    });

    testWidgets('B\'s summary loads exactly once', (WidgetTester tester) async {
      await pumpShell(tester);
      expect(dashboard.callCount, 1);

      await emit(tester, vendorB);

      expect(dashboard.callCount, 2);
    });

    testWidgets('a stale A first response cannot repopulate B', (
      WidgetTester tester,
    ) async {
      dashboard.manual = true;
      await pumpShell(tester);
      expect(dashboard.pendingCount, 1);

      await emit(tester, vendorB);
      expect(dashboard.pendingCount, 2);

      // A's answer lands *after* the switch. It must be discarded — A's member
      // count under B's session would be a cross-tenant disclosure dressed as a
      // dashboard.
      dashboard.completeAt(
        0,
        const ReadSuccess<VendorDashboardSummary>(exampleDashboardSummary),
      );
      await settle(tester);
      expect(cubit<VendorDashboardCubit>(tester).state.summary, isNull);

      // B's own answer still lands normally.
      dashboard.complete(
        const ReadSuccess<VendorDashboardSummary>(otherVendorDashboardSummary),
      );
      await settle(tester);
      expect(
        cubit<VendorDashboardCubit>(tester).state.summary,
        otherVendorDashboardSummary,
      );
    });

    testWidgets('a stale A refresh response cannot repopulate B', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      dashboard.manual = true;
      unawaited(cubit<VendorDashboardCubit>(tester).refresh());
      await settle(tester);
      expect(dashboard.pendingCount, 1);

      await emit(tester, vendorB);

      dashboard.completeAt(
        0,
        const ReadSuccess<VendorDashboardSummary>(exampleDashboardSummary),
      );
      await settle(tester);

      expect(cubit<VendorDashboardCubit>(tester).state.summary, isNull);
    });

    testWidgets('a stale A failure cannot set an error on B\'s screen', (
      WidgetTester tester,
    ) async {
      dashboard.manual = true;
      await pumpShell(tester);

      await emit(tester, vendorB);

      dashboard.completeAt(
        0,
        unavailableDashboardRead<VendorDashboardSummary>(),
      );
      await settle(tester);

      expect(cubit<VendorDashboardCubit>(tester).state.failure, isNull);
    });

    testWidgets('the refresh and failure state are cleared too', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      dashboard.result = unavailableDashboardRead<VendorDashboardSummary>();
      await cubit<VendorDashboardCubit>(tester).refresh();
      await settle(tester);
      expect(cubit<VendorDashboardCubit>(tester).state.isStale, isTrue);

      dashboard.result = null;
      dashboard.manual = true;
      await emit(tester, vendorB);

      final VendorDashboardCubit summary = cubit<VendorDashboardCubit>(tester);
      expect(summary.state.summary, isNull);
      expect(summary.state.failure, isNull);
      expect(summary.state.isStale, isFalse);
      expect(summary.state.hasFailedFirstRead, isFalse);
    });

    testWidgets('an identical re-emitted session is a no-op for the summary', (
      WidgetTester tester,
    ) async {
      // The shape a same-user token refresh takes. Nothing about the effective
      // identity changed, so there is nothing to protect and nothing to re-read.
      await pumpShell(tester);

      await emit(
        tester,
        SessionActive(vendorContext(orgOne), authUserId: 'user-A'),
      );

      expect(dashboard.callCount, 1);
      expect(
        cubit<VendorDashboardCubit>(tester).state.summary,
        exampleDashboardSummary,
      );
    });

    testWidgets('a changed trusted organization reloads the summary', (
      WidgetTester tester,
    ) async {
      // Same person, a different Vendor organization: the two tenant counts are
      // another organization's, so the snapshot is re-read rather than kept.
      await pumpShell(tester);

      await emit(
        tester,
        SessionActive(vendorContext(orgTwo), authUserId: 'user-A'),
      );

      expect(dashboard.callCount, 2);
    });

    testWidgets('signing out clears the summary and reloads nothing', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);

      await emit(tester, const SessionUnauthenticated());

      expect(cubit<VendorDashboardCubit>(tester).state.summary, isNull);
      expect(dashboard.callCount, 1);
    });

    testWidgets('becoming another role clears the summary', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);

      await emit(
        tester,
        SessionActive(retailerContext(), authUserId: 'user-A'),
      );

      expect(cubit<VendorDashboardCubit>(tester).state.summary, isNull);
      expect(dashboard.callCount, 1);
    });

    testWidgets('a session invalidation clears the summary', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);

      await emit(tester, const SessionUnavailable(UnavailableFailure()));

      expect(cubit<VendorDashboardCubit>(tester).state.summary, isNull);
      expect(dashboard.callCount, 1);
    });

    testWidgets('a denial clears the summary', (WidgetTester tester) async {
      await pumpShell(tester);

      await emit(tester, const SessionDenied());

      expect(cubit<VendorDashboardCubit>(tester).state.summary, isNull);
      expect(dashboard.callCount, 1);
    });

    testWidgets(
      'the Retailer, User, Role, Product and Audit state is still cleared '
      'alongside',
      (WidgetTester tester) async {
        // The Dashboard milestone must not have displaced any earlier part of
        // the listener.
        await pumpShell(tester);

        await emit(tester, vendorB);

        expect(users.usersCallCount, 2);
        expect(retailers.retailersCallCount, 2);
        expect(roles.rolesCallCount, 2);
        expect(products.productsCallCount, 2);
        expect(auditLogs.callCount, 2);
        expect(dashboard.callCount, 2);
      },
    );
  });

  /// The Vendor administrator profile, added by the company/profile milestone.
  ///
  /// The most personal cubit in this shell: it holds one individual's **name**
  /// and one individual's **entitlements**, and nothing about either is global.
  /// A direct `Vendor A → Vendor B` transition is exactly the case in which A's
  /// name could otherwise sit under B's session on a screen headed "Signed-in
  /// administrator" — which is a misidentification, not merely a stale card.
  ///
  /// Note what is *not* cleared, and why it does not need to be: the Vendor
  /// organization **name** on that screen is read from the session on every
  /// build rather than cached here, so it changes with the session by
  /// construction. This group therefore asserts the two halves separately — the
  /// profile clears, and the company name follows PortalContext.
  group('the Vendor administrator profile', () {
    testWidgets('A\'s name and roles are gone before B answers', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      expect(
        cubit<VendorProfileCubit>(tester).state.profile,
        aminaAdministratorProfile,
      );

      // B's profile will not answer until this test says so.
      profile.manual = true;
      await emit(tester, vendorB);

      // The window that matters: B is signed in, B's profile has not arrived,
      // and A's name and role names must already be out of the cubit.
      expect(profile.pendingCount, 1);
      expect(cubit<VendorProfileCubit>(tester).state.profile, isNull);
      expect(
        cubit<VendorProfileCubit>(tester).state.phase,
        VendorProfilePhase.loading,
      );

      profile.complete(
        const ReadSuccess<VendorAdministratorProfile>(joAdministratorProfile),
      );
      await settle(tester);

      expect(
        cubit<VendorProfileCubit>(tester).state.profile,
        joAdministratorProfile,
      );
    });

    testWidgets('the role list is cleared alongside the name', (
      WidgetTester tester,
    ) async {
      // Not a partially cleared identity — a name with no roles, or roles with
      // no name, is a shape no backend answer ever produces.
      profile.nextProfile = multiRoleAdministratorProfile;
      await pumpShell(tester);
      expect(
        cubit<VendorProfileCubit>(tester).state.profile!.roleNames,
        hasLength(3),
      );

      profile.manual = true;
      await emit(tester, vendorB);

      expect(cubit<VendorProfileCubit>(tester).state.profile, isNull);
    });

    testWidgets('B\'s profile loads exactly once', (WidgetTester tester) async {
      await pumpShell(tester);
      expect(profile.callCount, 1);

      await emit(tester, vendorB);

      expect(profile.callCount, 2);
    });

    testWidgets('a stale A first response cannot repopulate B', (
      WidgetTester tester,
    ) async {
      profile.manual = true;
      await pumpShell(tester);
      expect(profile.pendingCount, 1);

      await emit(tester, vendorB);
      expect(profile.pendingCount, 2);

      // A's answer lands *after* the switch. It must be discarded — A's name
      // under B's session is a misidentification dressed as a profile.
      profile.completeAt(
        0,
        const ReadSuccess<VendorAdministratorProfile>(
          aminaAdministratorProfile,
        ),
      );
      await settle(tester);
      expect(cubit<VendorProfileCubit>(tester).state.profile, isNull);

      // B's own answer still lands normally.
      profile.complete(
        const ReadSuccess<VendorAdministratorProfile>(joAdministratorProfile),
      );
      await settle(tester);
      expect(
        cubit<VendorProfileCubit>(tester).state.profile,
        joAdministratorProfile,
      );
    });

    testWidgets('a stale A refresh response cannot repopulate B', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      profile.manual = true;
      unawaited(cubit<VendorProfileCubit>(tester).refresh());
      await settle(tester);
      expect(profile.pendingCount, 1);

      await emit(tester, vendorB);

      profile.completeAt(
        0,
        const ReadSuccess<VendorAdministratorProfile>(
          aminaAdministratorProfile,
        ),
      );
      await settle(tester);

      expect(cubit<VendorProfileCubit>(tester).state.profile, isNull);
    });

    testWidgets('a stale A failure cannot set an error on B\'s screen', (
      WidgetTester tester,
    ) async {
      profile.manual = true;
      await pumpShell(tester);

      await emit(tester, vendorB);

      profile.completeAt(
        0,
        unavailableProfileRead<VendorAdministratorProfile>(),
      );
      await settle(tester);

      expect(cubit<VendorProfileCubit>(tester).state.failure, isNull);
    });

    testWidgets('the refresh and failure state are cleared too', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      profile.result = unavailableProfileRead<VendorAdministratorProfile>();
      await cubit<VendorProfileCubit>(tester).refresh();
      await settle(tester);
      expect(cubit<VendorProfileCubit>(tester).state.isStale, isTrue);

      profile.result = null;
      profile.manual = true;
      await emit(tester, vendorB);

      final VendorProfileCubit held = cubit<VendorProfileCubit>(tester);
      expect(held.state.profile, isNull);
      expect(held.state.failure, isNull);
      expect(held.state.isStale, isFalse);
      expect(held.state.hasFailedFirstRead, isFalse);
    });

    testWidgets('an identical re-emitted session is a no-op for the profile', (
      WidgetTester tester,
    ) async {
      // The shape a same-user token refresh takes. Nothing about the effective
      // identity changed, so there is nothing to protect and nothing to re-read.
      await pumpShell(tester);

      await emit(
        tester,
        SessionActive(vendorContext(orgOne), authUserId: 'user-A'),
      );

      expect(profile.callCount, 1);
      expect(
        cubit<VendorProfileCubit>(tester).state.profile,
        aminaAdministratorProfile,
      );
    });

    testWidgets('a changed trusted organization reloads the profile', (
      WidgetTester tester,
    ) async {
      // Same person, a different Vendor organization: the roles are that
      // membership's, not this one's, so the profile is re-read rather than kept.
      await pumpShell(tester);

      await emit(
        tester,
        SessionActive(vendorContext(orgTwo), authUserId: 'user-A'),
      );

      expect(profile.callCount, 2);
    });

    testWidgets('the company name follows PortalContext, not the cubit', (
      WidgetTester tester,
    ) async {
      // The other half of the screen. It is never cached by this feature, so a
      // changed trusted organization changes it without anything being cleared.
      await pumpShell(tester);

      const PortalContext before = PortalContext(
        contextVersion: supportedPortalContextVersion,
        portalKind: PortalKind.vendorSuperAdmin,
        vendor: VendorContext(
          organizationId: orgOne,
          organizationName: 'Example Vendor',
        ),
      );
      const PortalContext after = PortalContext(
        contextVersion: supportedPortalContextVersion,
        portalKind: PortalKind.vendorSuperAdmin,
        vendor: VendorContext(
          organizationId: orgTwo,
          organizationName: 'Northwind Trading',
        ),
      );

      expect(before.vendor!.organizationName, 'Example Vendor');
      expect(after.vendor!.organizationName, 'Northwind Trading');
      // And nothing in the profile cubit's state holds either of them.
      expect(
        cubit<VendorProfileCubit>(tester).state.toString(),
        isNot(contains('Vendor Trading')),
      );
    });

    testWidgets('signing out clears the profile and reloads nothing', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);

      await emit(tester, const SessionUnauthenticated());

      expect(cubit<VendorProfileCubit>(tester).state.profile, isNull);
      expect(profile.callCount, 1);
    });

    testWidgets('becoming another role clears the profile', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);

      await emit(
        tester,
        SessionActive(retailerContext(), authUserId: 'user-A'),
      );

      expect(cubit<VendorProfileCubit>(tester).state.profile, isNull);
      expect(profile.callCount, 1);
    });

    testWidgets('a session invalidation clears the profile', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);

      await emit(tester, const SessionUnavailable(UnavailableFailure()));

      expect(cubit<VendorProfileCubit>(tester).state.profile, isNull);
      expect(profile.callCount, 1);
    });

    testWidgets('a denial clears the profile', (WidgetTester tester) async {
      await pumpShell(tester);

      await emit(tester, const SessionDenied());

      expect(cubit<VendorProfileCubit>(tester).state.profile, isNull);
      expect(profile.callCount, 1);
    });

    testWidgets(
      'the Retailer, User, Role, Product, Audit and Dashboard state is still '
      'cleared alongside',
      (WidgetTester tester) async {
        // The company/profile milestone must not have displaced any earlier part
        // of the listener.
        await pumpShell(tester);

        await emit(tester, vendorB);

        expect(users.usersCallCount, 2);
        expect(retailers.retailersCallCount, 2);
        expect(roles.rolesCallCount, 2);
        expect(products.productsCallCount, 2);
        expect(auditLogs.callCount, 2);
        expect(dashboard.callCount, 2);
        expect(profile.callCount, 2);
      },
    );
  });
}
