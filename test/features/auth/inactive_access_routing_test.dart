import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/app/shells/retailer_manager/retailer_manager_shell.dart';
import 'package:sale_reward/app/shells/retailer_owner/retailer_owner_shell.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_shell.dart';
import 'package:sale_reward/app/shells/vendor/vendor_shell.dart';
import 'package:sale_reward/app/theme/app_theme.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/auth/domain/entities/auth_user.dart';
import 'package:sale_reward/features/auth/domain/entities/lifecycle_access_state.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/auth/domain/repositories/auth_repository.dart';
import 'package:sale_reward/features/auth/domain/repositories/lifecycle_access_repository.dart';
import 'package:sale_reward/features/auth/presentation/bloc/session_bloc.dart';
import 'package:sale_reward/features/auth/presentation/pages/access_denied_page.dart';
import 'package:sale_reward/features/auth/presentation/pages/login_page.dart';
import 'package:sale_reward/features/auth/presentation/pages/splash_page.dart';
import 'package:sale_reward/features/auth/presentation/pages/unavailable_page.dart';

import '../../support/fakes.dart';
import '../../support/lifecycle_access_fakes.dart';
import '../../support/pump_app.dart';

const AuthUser _otherUser = AuthUser(id: 'user-2', email: 'other@example.com');

Future<PumpedApp> pumpDenied(
  WidgetTester tester,
  FakeLifecycleAccessRepository fake, {
  bool settle = true,
}) => pumpApp(
  tester,
  initialUser: testUser,
  portalResult: deniedResult,
  lifecycleAccess: fake,
  settle: settle,
);

void main() {
  group('the automatic request is gated on a denied session', () {
    testWidgets('a denied session mounts exactly one diagnostic request', (
      WidgetTester tester,
    ) async {
      final FakeLifecycleAccessRepository fake = FakeLifecycleAccessRepository()
        ..result = const LifecycleAccessResolved(
          LifecycleAccessState.organizationInactive,
        );

      await pumpDenied(tester, fake);

      expect(find.byType(AccessDeniedPage), findsOneWidget);
      expect(fake.callCount, 1);
    });

    testWidgets(
      'the guard fallback runs no diagnostic when the session is not denied',
      (WidgetTester tester) async {
        // `_roleShell` renders AccessDeniedPage directly whenever the session is
        // not SessionActive for its own role, and pages co-mount for a frame or
        // two during a go_router transition. Mounting the page under a session
        // that has denied nothing must therefore ask nothing.
        final FakeAuthRepository auth = FakeAuthRepository(
          initialUser: testUser,
        );
        addTearDown(auth.dispose);
        final FakePortalContextRepository portal = FakePortalContextRepository(
          deniedResult,
        );
        final FakeLifecycleAccessRepository fake =
            FakeLifecycleAccessRepository();

        // Never started, so the bloc sits in SessionInitial.
        final SessionBloc session = SessionBloc(
          authRepository: auth,
          portalContextRepository: portal,
        );
        addTearDown(session.close);

        useSurface(tester, phoneSurface);
        await tester.pumpWidget(
          MultiRepositoryProvider(
            providers: <RepositoryProvider<Object>>[
              RepositoryProvider<AuthRepository>.value(value: auth),
              RepositoryProvider<LifecycleAccessRepository>.value(value: fake),
            ],
            child: BlocProvider<SessionBloc>.value(
              value: session,
              child: MaterialApp(
                theme: AppTheme.light,
                home: const AccessDeniedPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Access denied'), findsOneWidget);
        expect(fake.callCount, 0, reason: 'nothing was denied by the backend');
        // The fallback keeps exactly the screen it rendered before this feature.
        expect(find.widgetWithText(SrButton, 'Sign out'), findsOneWidget);
        expect(
          find.widgetWithText(SrButton, 'Check access again'),
          findsNothing,
        );
      },
    );
  });

  group('Check access again', () {
    testWidgets('passes through SessionResolving and shows the splash', (
      WidgetTester tester,
    ) async {
      final FakeLifecycleAccessRepository fake = FakeLifecycleAccessRepository()
        ..result = const LifecycleAccessResolved(
          LifecycleAccessState.organizationInactive,
        );
      final PumpedApp app = await pumpDenied(tester, fake);
      app.portal.manualCompletion = true;

      await tester.tap(find.widgetWithText(SrButton, 'Check access again'));
      // The splash bounce is INTENTIONAL: `sessionHome(SessionResolving)` is the
      // splash, and the retry on UnavailablePage has always behaved the same
      // way. It is asserted here so that removing it stays a deliberate
      // decision rather than an accident.
      //
      // Only asserted for a resolution slow enough for the router to act on. A
      // fast one collapses `Denied → Resolving → Denied` inside a frame and the
      // location never moves — which is exactly why the diagnostic is keyed on a
      // denied-episode counter rather than on this page's lifetime.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SplashPage), findsOneWidget);

      app.portal.completeNext(deniedResult);
      await tester.pumpAndSettle();

      // And the user is returned to a freshly explained denial.
      expect(find.byType(AccessDeniedPage), findsOneWidget);
      expect(find.byType(SplashPage), findsNothing);
      expect(fake.callCount, 2);
    });

    testWidgets('a fast continued denial still asks exactly once more', (
      WidgetTester tester,
    ) async {
      // The resolution completes immediately, so `Denied → Resolving → Denied`
      // collapses and the router never leaves `/access-denied`. The diagnostic
      // must refresh anyway — this is the case a mount-scoped cubit would miss.
      final FakeLifecycleAccessRepository fake = FakeLifecycleAccessRepository()
        ..result = const LifecycleAccessResolved(
          LifecycleAccessState.membershipInactive,
        );
      final PumpedApp app = await pumpDenied(tester, fake);
      expect(fake.callCount, 1);

      await tester.tap(find.widgetWithText(SrButton, 'Check access again'));
      await tester.pumpAndSettle();

      expect(find.byType(AccessDeniedPage), findsOneWidget);
      expect(find.text('Account inactive'), findsOneWidget);
      expect(app.portal.resolveCallCount, 2);
      expect(fake.callCount, 2, reason: 'one per denied episode, never more');
    });

    testWidgets('the refreshed copy follows a changed diagnostic', (
      WidgetTester tester,
    ) async {
      final FakeLifecycleAccessRepository fake = FakeLifecycleAccessRepository()
        ..result = const LifecycleAccessResolved(
          LifecycleAccessState.organizationInactive,
        );
      await pumpDenied(tester, fake);
      expect(find.text('Retailer inactive'), findsOneWidget);

      // The Retailer was reactivated but this member is still inactive.
      fake.result = const LifecycleAccessResolved(
        LifecycleAccessState.membershipInactive,
      );
      await tester.tap(find.widgetWithText(SrButton, 'Check access again'));
      await tester.pumpAndSettle();

      expect(find.text('Account inactive'), findsOneWidget);
      expect(find.text('Retailer inactive'), findsNothing);
    });
  });

  group('restoration routes through canonical portal context only', () {
    Future<void> expectRestores(
      WidgetTester tester,
      PortalKind kind,
      Type shell,
    ) async {
      final FakeLifecycleAccessRepository fake = FakeLifecycleAccessRepository()
        ..result = const LifecycleAccessResolved(
          LifecycleAccessState.organizationInactive,
        );
      final PumpedApp app = await pumpDenied(tester, fake);
      expect(find.text('Retailer inactive'), findsOneWidget);

      app.portal.result = resolvedResult(kind);
      await tester.tap(find.widgetWithText(SrButton, 'Check access again'));
      await tester.pumpAndSettle();

      expect(find.byType(shell), findsOneWidget);
      expect(find.byType(AccessDeniedPage), findsNothing);
      // No sign-out was needed to recover.
      expect(app.auth.signOutCallCount, 0);
    }

    testWidgets(
      'a restored Retailer Owner reaches the Owner shell',
      (WidgetTester tester) =>
          expectRestores(tester, PortalKind.retailerOwner, RetailerOwnerShell),
    );

    testWidgets(
      'a restored Retailer Manager reaches the Manager shell',
      (WidgetTester tester) => expectRestores(
        tester,
        PortalKind.retailerManager,
        RetailerManagerShell,
      ),
    );

    testWidgets(
      'a restored Sales Staff user reaches the Sales Staff shell',
      (WidgetTester tester) =>
          expectRestores(tester, PortalKind.salesStaff, SalesStaffShell),
    );

    testWidgets(
      'a restored Vendor Super Admin reaches the Vendor shell',
      (WidgetTester tester) =>
          expectRestores(tester, PortalKind.vendorSuperAdmin, VendorShell),
    );
  });

  group('the diagnostic never routes', () {
    testWidgets('a resolved ACTIVE leaves the user on the denied screen', (
      WidgetTester tester,
    ) async {
      final FakeLifecycleAccessRepository fake = FakeLifecycleAccessRepository()
        ..result = const LifecycleAccessResolved(LifecycleAccessState.active);

      await pumpDenied(tester, fake);
      // Well past any frame in which a navigation could have been scheduled.
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(AccessDeniedPage), findsOneWidget);
      expect(find.text('Access denied'), findsOneWidget);
      expect(find.byType(VendorShell), findsNothing);
      expect(find.byType(SalesStaffShell), findsNothing);
      expect(find.byType(LoginPage), findsNothing);
    });
  });

  group('operational failure keeps its own screen', () {
    testWidgets('a failed resolution reaches UnavailablePage, not the notice', (
      WidgetTester tester,
    ) async {
      final FakeLifecycleAccessRepository fake = FakeLifecycleAccessRepository()
        ..result = const LifecycleAccessResolved(
          LifecycleAccessState.organizationInactive,
        );
      final PumpedApp app = await pumpDenied(tester, fake);

      app.portal.result = unavailableResult;
      await tester.tap(find.widgetWithText(SrButton, 'Check access again'));
      await tester.pumpAndSettle();

      expect(find.byType(UnavailablePage), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      // An outage must never be dressed as a lifecycle explanation.
      expect(find.text('Retailer inactive'), findsNothing);
      expect(
        find.text('If this changes, use Check access again.'),
        findsNothing,
      );
    });
  });

  group('sign-out', () {
    testWidgets('signing out from a denied session reaches login', (
      WidgetTester tester,
    ) async {
      final FakeLifecycleAccessRepository fake = FakeLifecycleAccessRepository()
        ..result = const LifecycleAccessResolved(
          LifecycleAccessState.profileInactive,
        );
      await pumpDenied(tester, fake);

      await tester.tap(find.widgetWithText(SrButton, 'Sign out'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('Account unavailable'), findsNothing);
    });
  });

  group('a user switch never shows the previous person', () {
    testWidgets('a result in flight when the subject changes is dropped', (
      WidgetTester tester,
    ) async {
      final FakeLifecycleAccessRepository fake = FakeLifecycleAccessRepository()
        ..manual = true;
      final PumpedApp app = await pumpDenied(tester, fake, settle: false);
      await tester.pump();
      await tester.pump();

      expect(fake.pendingCount, 1);

      // Somebody else signs in while the first person's diagnostic is pending.
      app.portal.result = resolvedResult(PortalKind.salesStaff);
      app.auth.emitSignedIn(_otherUser);
      await tester.pumpAndSettle();

      // The new person is in their own portal, and the previous person's
      // explanation never rendered.
      expect(find.byType(SalesStaffShell), findsOneWidget);

      fake.complete(
        const LifecycleAccessResolved(LifecycleAccessState.profileInactive),
      );
      await tester.pumpAndSettle();

      expect(find.text('Account unavailable'), findsNothing);
      expect(find.byType(SalesStaffShell), findsOneWidget);
    });
  });
}
