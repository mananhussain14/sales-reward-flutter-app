import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_shell.dart';
import 'package:sale_reward/features/auth/domain/entities/lifecycle_access_state.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/auth/presentation/pages/access_denied_page.dart';
import 'package:sale_reward/features/auth/presentation/pages/splash_page.dart';

import '../../support/fakes.dart';
import '../../support/lifecycle_access_fakes.dart';
import '../../support/pump_app.dart';

Future<void> sendAppToBackgroundAndResume(WidgetTester tester) async {
  for (final AppLifecycleState state in <AppLifecycleState>[
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
}

void main() {
  group('application resume lifecycle revalidation', () {
    testWidgets(
      'a staff member deactivated while the app is backgrounded is routed '
      'to the correct inactive-account notice',
      (WidgetTester tester) async {
        final FakeLifecycleAccessRepository lifecycleAccess =
            FakeLifecycleAccessRepository()
              ..resolveWith(LifecycleAccessState.membershipInactive);

        final PumpedApp app = await pumpAppInRole(
          tester,
          PortalKind.salesStaff,
          lifecycleAccess: lifecycleAccess,
        );

        expect(find.byType(SalesStaffShell), findsOneWidget);
        expect(app.portal.resolveCallCount, 1);

        // The Retailer Owner deactivated this membership while the app was in
        // the background. The next portal-context resolution now denies access.
        app.portal.result = deniedResult;

        await sendAppToBackgroundAndResume(tester);
        await tester.pumpAndSettle();

        expect(app.portal.resolveCallCount, 2);
        expect(find.byType(AccessDeniedPage), findsOneWidget);
        expect(find.text('Account inactive'), findsOneWidget);
        expect(find.byType(SalesStaffShell), findsNothing);
        expect(lifecycleAccess.callCount, 1);
      },
    );

    testWidgets(
      'unchanged access keeps the existing shell mounted without a splash',
      (WidgetTester tester) async {
        final PumpedApp app = await pumpAppInRole(
          tester,
          PortalKind.salesStaff,
        );

        final Element shellBeforeResume = tester.element(
          find.byType(SalesStaffShell),
        );

        expect(app.portal.resolveCallCount, 1);

        await sendAppToBackgroundAndResume(tester);
        await tester.pumpAndSettle();

        expect(app.portal.resolveCallCount, 2);
        expect(find.byType(SalesStaffShell), findsOneWidget);
        expect(find.byType(SplashPage), findsNothing);
        expect(
          tester.element(find.byType(SalesStaffShell)),
          same(shellBeforeResume),
          reason: 'an unchanged revalidation must not remount the shell',
        );
      },
    );

    testWidgets(
      'repeated resume events while a revalidation is pending start one request',
      (WidgetTester tester) async {
        final PumpedApp app = await pumpAppInRole(
          tester,
          PortalKind.salesStaff,
        );

        app.portal.manualCompletion = true;

        await sendAppToBackgroundAndResume(tester);
        expect(app.portal.pendingCount, 1);
        expect(app.portal.resolveCallCount, 2);

        // A second foreground cycle arrives before the first revalidation has
        // completed. SessionBloc must collapse it into the existing request.
        await sendAppToBackgroundAndResume(tester);

        expect(app.portal.pendingCount, 1);
        expect(
          app.portal.resolveCallCount,
          2,
          reason: 'startup plus one applicable resume revalidation',
        );
        expect(find.byType(SalesStaffShell), findsOneWidget);
        expect(find.byType(SplashPage), findsNothing);

        app.portal.completeNext(resolvedResult(PortalKind.salesStaff));
        await tester.pumpAndSettle();

        expect(find.byType(SalesStaffShell), findsOneWidget);
      },
    );
  });
}
