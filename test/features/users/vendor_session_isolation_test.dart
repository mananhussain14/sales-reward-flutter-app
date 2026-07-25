import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/shells/vendor/vendor_shell.dart';
import 'package:sale_reward/app/theme/app_theme.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/core/result/read_result.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_context.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/auth/domain/entities/retailer_capabilities.dart';
import 'package:sale_reward/features/auth/presentation/bloc/session_bloc.dart';
import 'package:sale_reward/features/retailers/domain/repositories/vendor_retailer_repository.dart';
import 'package:sale_reward/features/retailers/presentation/vendor/cubit/vendor_retailer_detail_cubit.dart';
import 'package:sale_reward/features/retailers/presentation/vendor/cubit/vendor_retailer_list_cubit.dart';
import 'package:sale_reward/features/users/domain/entities/vendor_user_detail.dart';
import 'package:sale_reward/features/users/domain/entities/vendor_user_summary.dart';
import 'package:sale_reward/features/users/domain/repositories/vendor_user_repository.dart';
import 'package:sale_reward/features/users/presentation/vendor/cubit/vendor_user_detail_cubit.dart';
import 'package:sale_reward/features/users/presentation/vendor/cubit/vendor_user_list_cubit.dart';
import 'package:sale_reward/features/users/presentation/vendor/pages/vendor_users_page.dart';

import '../../support/pump_app.dart';
import '../../support/vendor_retailer_fakes.dart';
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

    // Force all four cubits into existence before any assertion counts calls.
    // `BlocProvider` builds each on first read, so without this the Retailer
    // pair would be created *by the session listener itself* and the call
    // counts would measure creation rather than reloading.
    cubit<VendorUserListCubit>(tester);
    cubit<VendorUserDetailCubit>(tester);
    cubit<VendorRetailerListCubit>(tester);
    cubit<VendorRetailerDetailCubit>(tester);
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
}
