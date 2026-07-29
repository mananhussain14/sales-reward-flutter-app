import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/shells/retailer_manager/retailer_manager_shell.dart';
import 'package:sale_reward/app/shells/retailer_owner/retailer_owner_shell.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_shell.dart';
import 'package:sale_reward/app/app.dart';
import 'package:sale_reward/app/shells/vendor/vendor_shell.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/auth/domain/entities/auth_user.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/auth/domain/repositories/auth_repository.dart';
import 'package:sale_reward/features/auth/presentation/pages/login_page.dart';
import 'package:sale_reward/features/auth/presentation/pages/splash_page.dart';
import 'package:sale_reward/features/auth/presentation/pages/unavailable_page.dart';

import '../support/fakes.dart';
import '../support/retailer_owner_overview_fakes.dart';
import '../support/retailer_invite_staff_fakes.dart';
import '../support/retailer_manage_staff_shops_fakes.dart';
import '../support/retailer_staff_lifecycle_fakes.dart';
import '../support/retailer_read_fakes.dart';
import '../support/pump_app.dart';
import '../support/vendor_audit_log_fakes.dart';
import '../support/vendor_dashboard_fakes.dart';
import '../support/receipt_fakes.dart';
import '../support/vendor_retailer_fakes.dart';
import '../support/vendor_retailer_lifecycle_fakes.dart';
import '../support/vendor_product_fakes.dart';
import '../support/vendor_profile_fakes.dart';
import '../support/vendor_role_fakes.dart';
import '../support/vendor_user_fakes.dart';

/// The whole flow, driven through the real widget tree over fakes.
void main() {
  const Map<PortalKind, Type> shellFor = <PortalKind, Type>{
    PortalKind.vendorSuperAdmin: VendorShell,
    PortalKind.retailerOwner: RetailerOwnerShell,
    PortalKind.retailerManager: RetailerManagerShell,
    PortalKind.salesStaff: SalesStaffShell,
  };

  group('startup', () {
    testWidgets('with no session shows the login screen', (tester) async {
      await pumpApp(tester); // no initialUser

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
    });

    for (final MapEntry<PortalKind, Type> entry in shellFor.entries) {
      testWidgets('a restored ${entry.key.name} session reaches its shell', (
        tester,
      ) async {
        await pumpAppInRole(tester, entry.key);
        expect(find.byType(entry.value), findsOneWidget);
        // No other shell is in the tree.
        for (final Type other in shellFor.values) {
          if (other == entry.value) continue;
          expect(find.byType(other), findsNothing);
        }
      });
    }

    testWidgets('a NONE answer routes to access denied', (tester) async {
      await pumpApp(tester, initialUser: testUser, portalResult: deniedResult);

      expect(find.byType(SrAccessDeniedView), findsOneWidget);
      expect(find.text('Access denied'), findsOneWidget);
    });

    testWidgets('a resolve failure routes to the retry screen', (tester) async {
      await pumpApp(
        tester,
        initialUser: testUser,
        portalResult: unavailableResult,
      );

      expect(find.byType(UnavailablePage), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      // A failure is not a denial.
      expect(find.byType(SrAccessDeniedView), findsNothing);
    });

    testWidgets('no shell flashes before resolution completes', (tester) async {
      final FakePortalContextRepository portal = FakePortalContextRepository(
        resolvedResult(PortalKind.vendorSuperAdmin),
      )..delay = const Duration(milliseconds: 200);
      final FakeAuthRepository auth = FakeAuthRepository(initialUser: testUser);
      addTearDown(auth.dispose);

      useSurface(tester, phoneSurface);
      await tester.pumpWidget(
        SaleRewardApp(
          authRepository: auth,
          portalContextRepository: portal,
          receiptRepository: FakeReceiptRepository(),
          receiptImageSource: FakeReceiptImageSource(),
          vendorRetailerRepository: FakeVendorRetailerRepository(),
          vendorRetailerLifecycleRepository:
              FakeVendorRetailerLifecycleRepository(),
          vendorUserRepository: FakeVendorUserRepository(),
          vendorRoleRepository: FakeVendorRoleRepository(),
          vendorProductRepository: FakeVendorProductRepository(),
          vendorAuditLogRepository: FakeVendorAuditLogRepository(),
          vendorDashboardRepository: FakeVendorDashboardRepository(),
          vendorProfileRepository: FakeVendorProfileRepository(),
          retailerOwnerOverviewRepository:
              FakeRetailerOwnerOverviewRepository(),
          retailerShopRepository: FakeRetailerShopRepository(),
          retailerStaffRepository: FakeRetailerStaffRepository(),
          retailerStaffInvitationRepository:
              FakeRetailerStaffInvitationRepository(),
          retailerStaffLifecycleRepository:
              FakeRetailerStaffLifecycleRepository(),
          retailerStaffShopAssignmentRepository:
              FakeRetailerStaffShopAssignmentRepository(),
          retailerProductRepository: FakeRetailerProductRepository(),
        ),
      );

      // While the RPC is in flight, the splash holds the frame — never a shell.
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(SplashPage), findsOneWidget);
      expect(find.byType(VendorShell), findsNothing);

      await tester.pumpAndSettle();
      expect(find.byType(VendorShell), findsOneWidget);
    });
  });

  group('login', () {
    testWidgets('a successful sign-in resolves and routes to the shell', (
      tester,
    ) async {
      final PumpedApp app = await pumpApp(
        tester,
        portalResult: resolvedResult(PortalKind.salesStaff),
      );
      expect(find.byType(LoginPage), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'sam@example.com');
      await tester.enterText(find.byType(TextField).last, 'secret');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(app.auth.signInCallCount, 1);
      expect(find.byType(SalesStaffShell), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
    });

    testWidgets('invalid credentials stay on login with a generic error', (
      tester,
    ) async {
      final PumpedApp app = await pumpApp(tester);
      app.auth.nextSignInResult = const SignInRejected();

      await tester.enterText(find.byType(TextField).first, 'sam@example.com');
      await tester.enterText(find.byType(TextField).last, 'nope');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.textContaining('do not match an account'), findsOneWidget);
    });
  });

  group('logout', () {
    testWidgets('signing out clears the shell and shows login', (tester) async {
      await pumpAppInRole(tester, PortalKind.retailerOwner);
      expect(find.byType(RetailerOwnerShell), findsOneWidget);

      // Open the account sheet from the app-bar avatar.
      await tester.tap(find.bySemanticsLabel('Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SrButton, 'Sign out'));
      await tester.pumpAndSettle();

      // Confirm the dialog — its own "Sign out" button, not the sheet's.
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, 'Sign out'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RetailerOwnerShell), findsNothing);
      expect(find.byType(LoginPage), findsOneWidget);
    });
  });

  group('token refresh', () {
    testWidgets('does not log the user out or leave the shell', (tester) async {
      final PumpedApp app = await pumpAppInRole(
        tester,
        PortalKind.vendorSuperAdmin,
      );
      expect(find.byType(VendorShell), findsOneWidget);

      app.auth.emitTokenRefreshed(testUser);
      await tester.pumpAndSettle();

      expect(find.byType(VendorShell), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
      // The refresh triggered no second resolution.
      expect(app.portal.resolveCallCount, 1);
    });
  });

  group('manual cross-role navigation', () {
    testWidgets('a Sales Staff user cannot reach the Vendor shell by URL', (
      tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);
      expect(find.byType(SalesStaffShell), findsOneWidget);

      final BuildContext context = tester.element(find.byType(Scaffold).first);
      context.go('/vendor/dashboard');
      await tester.pumpAndSettle();

      // Redirected back to the Sales Staff shell; the Vendor shell never built.
      expect(find.byType(VendorShell), findsNothing);
      expect(find.byType(SalesStaffShell), findsOneWidget);
    });
  });

  group('retry', () {
    testWidgets('retry after a failure resolves and routes to the shell', (
      tester,
    ) async {
      final PumpedApp app = await pumpApp(
        tester,
        initialUser: testUser,
        portalResult: unavailableResult,
      );
      expect(find.byType(UnavailablePage), findsOneWidget);

      // The backend recovers; retry now succeeds.
      app.portal.result = resolvedResult(PortalKind.retailerManager);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.byType(RetailerManagerShell), findsOneWidget);
      expect(find.byType(UnavailablePage), findsNothing);
    });
  });
  group('logout race (invariant 8)', () {
    testWidgets(
      'a stale resolution completing after logout never restores the shell',
      (tester) async {
        // Startup resolution is held pending, so the app sits on the splash.
        final FakeAuthRepository auth = FakeAuthRepository(
          initialUser: testUser,
        );
        final FakePortalContextRepository portal = FakePortalContextRepository(
          resolvedResult(PortalKind.vendorSuperAdmin),
        )..manualCompletion = true;
        addTearDown(auth.dispose);

        useSurface(tester, phoneSurface);
        await tester.pumpWidget(
          SaleRewardApp(
            authRepository: auth,
            portalContextRepository: portal,
            receiptRepository: FakeReceiptRepository(),
            receiptImageSource: FakeReceiptImageSource(),
            vendorRetailerRepository: FakeVendorRetailerRepository(),
            vendorRetailerLifecycleRepository:
                FakeVendorRetailerLifecycleRepository(),
            vendorUserRepository: FakeVendorUserRepository(),
            vendorRoleRepository: FakeVendorRoleRepository(),
            vendorProductRepository: FakeVendorProductRepository(),
            vendorAuditLogRepository: FakeVendorAuditLogRepository(),
            vendorDashboardRepository: FakeVendorDashboardRepository(),
            vendorProfileRepository: FakeVendorProfileRepository(),
            retailerOwnerOverviewRepository:
                FakeRetailerOwnerOverviewRepository(),
            retailerShopRepository: FakeRetailerShopRepository(),
            retailerStaffRepository: FakeRetailerStaffRepository(),
            retailerStaffInvitationRepository:
                FakeRetailerStaffInvitationRepository(),
            retailerStaffLifecycleRepository:
                FakeRetailerStaffLifecycleRepository(),
            retailerStaffShopAssignmentRepository:
                FakeRetailerStaffShopAssignmentRepository(),
            retailerProductRepository: FakeRetailerProductRepository(),
          ),
        );
        await tester.pump();
        expect(find.byType(SplashPage), findsOneWidget);

        // Sign out while the resolution is still in flight.
        auth.emitSignedOut();
        await tester.pumpAndSettle();
        expect(find.byType(LoginPage), findsOneWidget);

        // The stale resolution now completes — the Vendor shell must NOT appear.
        portal.completeNext();
        await tester.pumpAndSettle();

        expect(find.byType(VendorShell), findsNothing);
        expect(find.byType(LoginPage), findsOneWidget);
      },
    );

    testWidgets(
      'a stale A resolution completing after switching to B never shows A',
      (tester) async {
        final FakeAuthRepository auth = FakeAuthRepository(
          initialUser: testUser, // user A
        );
        final FakePortalContextRepository portal = FakePortalContextRepository(
          resolvedResult(PortalKind.vendorSuperAdmin),
        )..manualCompletion = true;
        addTearDown(auth.dispose);

        useSurface(tester, phoneSurface);
        await tester.pumpWidget(
          SaleRewardApp(
            authRepository: auth,
            portalContextRepository: portal,
            receiptRepository: FakeReceiptRepository(),
            receiptImageSource: FakeReceiptImageSource(),
            vendorRetailerRepository: FakeVendorRetailerRepository(),
            vendorRetailerLifecycleRepository:
                FakeVendorRetailerLifecycleRepository(),
            vendorUserRepository: FakeVendorUserRepository(),
            vendorRoleRepository: FakeVendorRoleRepository(),
            vendorProductRepository: FakeVendorProductRepository(),
            vendorAuditLogRepository: FakeVendorAuditLogRepository(),
            vendorDashboardRepository: FakeVendorDashboardRepository(),
            vendorProfileRepository: FakeVendorProfileRepository(),
            retailerOwnerOverviewRepository:
                FakeRetailerOwnerOverviewRepository(),
            retailerShopRepository: FakeRetailerShopRepository(),
            retailerStaffRepository: FakeRetailerStaffRepository(),
            retailerStaffInvitationRepository:
                FakeRetailerStaffInvitationRepository(),
            retailerStaffLifecycleRepository:
                FakeRetailerStaffLifecycleRepository(),
            retailerStaffShopAssignmentRepository:
                FakeRetailerStaffShopAssignmentRepository(),
            retailerProductRepository: FakeRetailerProductRepository(),
          ),
        );
        await tester.pump();

        // User B signs in while A is pending.
        auth.emitSignedIn(const AuthUser(id: 'user-B', email: 'b@example.com'));
        await tester.pump();

        // A completes first (stale), then B.
        portal.completeNext(resolvedResult(PortalKind.vendorSuperAdmin)); // A
        await tester.pump();
        expect(find.byType(VendorShell), findsNothing);

        portal.completeNext(resolvedResult(PortalKind.salesStaff)); // B
        await tester.pumpAndSettle();

        expect(find.byType(SalesStaffShell), findsOneWidget);
        expect(find.byType(VendorShell), findsNothing);
      },
    );
  });
}
