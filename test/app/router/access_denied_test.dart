import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/router/app_router.dart';
import 'package:sale_reward/app/router/app_routes.dart';
import 'package:sale_reward/app/theme/app_theme.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/auth/domain/entities/app_role.dart';
import 'package:sale_reward/features/auth/presentation/bloc/role_session_bloc.dart';
import 'package:sale_reward/features/auth/presentation/pages/role_gate_page.dart';

import '../../support/pump_app.dart';

// Access-denied behaviour.
//
// The screen must be ROLE-NEUTRAL and REASON-FREE. It is reached both by a
// caller the backend refused entirely and by a caller who wandered into another
// role's routes, and those two must be indistinguishable — otherwise the
// difference itself is information a hostile account can enumerate. The
// backend's deliberately overloaded `42501` exists for the same reason.

/// Navigates the live app.
///
/// The context is re-acquired on every call: a `BuildContext` captured before a
/// navigation is deactivated by it and must not be reused.
void _navigate(WidgetTester tester, String location) {
  tester.element(find.byType(Scaffold).first).go(location);
}

void main() {
  group('the shared access-denied screen', () {
    Future<void> pumpView(WidgetTester tester) async {
      useSurface(tester, phoneSurface);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const SrAccessDeniedView()),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders the neutral heading and the brand lockup', (
      tester,
    ) async {
      await pumpView(tester);

      expect(find.text('Access denied'), findsOneWidget);
      expect(find.byType(SrBrandLockup), findsOneWidget);
    });

    testWidgets('names no role', (tester) async {
      await pumpView(tester);

      for (final AppRole role in AppRole.values) {
        expect(
          find.textContaining(role.displayName),
          findsNothing,
          reason:
              'naming ${role.displayName} would tell the caller which check '
              'refused them',
        );
      }
    });

    testWidgets('gives no reason and names no record', (tester) async {
      await pumpView(tester);

      // "not found", "no such", "does not exist" would turn a denial into an
      // existence oracle — exactly what the backend's overloaded 42501 avoids.
      for (final String forbidden in <String>[
        'not found',
        'does not exist',
        'no such',
        'invalid',
        'expired',
      ]) {
        expect(
          find.textContaining(forbidden, findRichText: true),
          findsNothing,
          reason: '"$forbidden" leaks why the caller was refused',
        );
      }
    });

    testWidgets('always offers a way out', (tester) async {
      await pumpView(tester);

      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('disables the sign-out control when no handler is wired', (
      tester,
    ) async {
      await pumpView(tester);

      final TextButton button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Sign out'),
      );

      // Shown-but-inert rather than hidden, so the screen's shape does not
      // change once authentication lands.
      expect(button.onPressed, isNull);
    });
  });

  group('reaching access-denied', () {
    testWidgets('a wrong-role deep link lands here', (tester) async {
      await pumpAppInRole(tester, AppRole.salesStaff);

      _navigate(tester, '/vendor/dashboard');
      await tester.pumpAndSettle();

      expect(find.byType(SrAccessDeniedView), findsOneWidget);
      expect(find.text('Access denied'), findsOneWidget);
    });

    testWidgets('the two entry paths render the same screen', (tester) async {
      await pumpAppInRole(tester, AppRole.salesStaff);

      // Reached by guard redirect.
      _navigate(tester, '/vendor/dashboard');
      await tester.pumpAndSettle();
      final int viaGuard = find.text('Access denied').evaluate().length;

      // Reached directly.
      _navigate(tester, AppRoutes.accessDenied);
      await tester.pumpAndSettle();
      final int viaDirect = find.text('Access denied').evaluate().length;

      expect(viaGuard, viaDirect);
      expect(find.byType(SrAccessDeniedView), findsOneWidget);
    });

    testWidgets('signing out clears the role and returns to the gate', (
      tester,
    ) async {
      await pumpAppInRole(tester, AppRole.salesStaff);

      _navigate(tester, AppRoutes.accessDenied);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
      await tester.pumpAndSettle();

      expect(find.byType(RoleGatePage), findsOneWidget);
      expect(find.byType(SrAccessDeniedView), findsNothing);

      // The preview role is gone: the shell is not reachable again without
      // choosing one.
      expect(find.textContaining('Interface preview'), findsNothing);
    });
  });

  group('a caller with no supported role', () {
    test('lands on access-denied rather than a shell', () {
      expect(
        redirectFor(const RoleSessionNoAccess(), AppRoutes.roleGate),
        AppRoutes.accessDenied,
      );
    });

    test('is refused every role group', () {
      for (final AppRole role in AppRole.values) {
        expect(
          redirectFor(
            const RoleSessionNoAccess(),
            '/${role.wireKind}-does-not-matter',
          ),
          anyOf(isNull, AppRoutes.roleGate),
          reason: 'an unknown path is never treated as a role group',
        );
      }
    });
  });
}
