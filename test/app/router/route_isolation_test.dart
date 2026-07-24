import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/navigation/role_destination.dart';
import 'package:sale_reward/app/navigation/role_navigation_registry.dart';
import 'package:sale_reward/app/router/app_router.dart';
import 'package:sale_reward/app/router/app_routes.dart';
import 'package:sale_reward/app/shells/retailer_manager/retailer_manager_shell.dart';
import 'package:sale_reward/app/shells/retailer_owner/retailer_owner_shell.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_shell.dart';
import 'package:sale_reward/app/shells/vendor/vendor_shell.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/auth/domain/entities/app_role.dart';
import 'package:sale_reward/features/auth/presentation/bloc/role_session_bloc.dart';

import '../../support/pump_app.dart';

/// Route isolation.
///
/// The property under test: **a role can only be inside its own route group.**
///
/// This is a presentation guard, not a security boundary — Supabase re-decides
/// every operation in SQL regardless. What it buys is that a user never lands in
/// a shell whose every query would fail, and that "which screens can this role
/// reach?" has a single, checkable answer.
void main() {
  group('route prefixes do not overlap', () {
    test('every role owns a distinct prefix', () {
      final Set<String> prefixes = RoleNavigationRegistry.ordered
          .map((RoleNavigation n) => n.routePrefix)
          .toSet();

      expect(prefixes, hasLength(AppRole.values.length));
    });

    test('no prefix is a prefix of another', () {
      for (final RoleNavigation a in RoleNavigationRegistry.ordered) {
        for (final RoleNavigation b in RoleNavigationRegistry.ordered) {
          if (identical(a, b)) continue;
          expect(
            a.routePrefix.startsWith('${b.routePrefix}/'),
            isFalse,
            reason: '${a.routePrefix} nests inside ${b.routePrefix}',
          );
        }
      }
    });

    test('every routable destination lives under its own role\'s prefix', () {
      for (final RoleNavigation navigation in RoleNavigationRegistry.ordered) {
        for (final RoleDestination destination
            in navigation.routableDestinations) {
          expect(
            navigation.owns(destination.path!),
            isTrue,
            reason:
                '${destination.path} is offered by ${navigation.role.name} but '
                'is not under ${navigation.routePrefix}',
          );
        }
      }
    });

    test('no path is claimed by two roles', () {
      final Map<String, AppRole> seen = <String, AppRole>{};

      for (final RoleNavigation navigation in RoleNavigationRegistry.ordered) {
        for (final RoleDestination destination
            in navigation.routableDestinations) {
          expect(
            seen.containsKey(destination.path!),
            isFalse,
            reason:
                '${destination.path} is claimed by both '
                '${seen[destination.path]?.name} and ${navigation.role.name}',
          );
          seen[destination.path!] = navigation.role;
        }
      }
    });

    test('roleOwning resolves each destination to its own role', () {
      for (final RoleNavigation navigation in RoleNavigationRegistry.ordered) {
        for (final RoleDestination destination
            in navigation.routableDestinations) {
          expect(
            RoleNavigationRegistry.roleOwning(destination.path!),
            navigation.role,
          );
        }
      }
    });

    test('roleOwning claims neither shared route', () {
      expect(RoleNavigationRegistry.roleOwning(AppRoutes.roleGate), isNull);
      expect(RoleNavigationRegistry.roleOwning(AppRoutes.accessDenied), isNull);
    });
  });

  group('the route guard', () {
    RoleSessionState active(AppRole role) =>
        RoleSessionActive(ResolvedRole.preview(role));

    test('sends a role with no session back to the gate', () {
      for (final RoleNavigation navigation in RoleNavigationRegistry.ordered) {
        expect(
          redirectFor(const RoleSessionInitial(), navigation.landingPath),
          AppRoutes.roleGate,
          reason: 'fail closed: no role means no shell',
        );
      }
    });

    test('sends a mismatched role to access-denied', () {
      for (final AppRole role in AppRole.values) {
        for (final RoleNavigation other in RoleNavigationRegistry.ordered) {
          if (other.role == role) continue;

          expect(
            redirectFor(active(role), other.landingPath),
            AppRoutes.accessDenied,
            reason: '${role.displayName} must not reach ${other.landingPath}',
          );
        }
      }
    });

    test('allows a role inside its own group', () {
      for (final RoleNavigation navigation in RoleNavigationRegistry.ordered) {
        for (final RoleDestination destination
            in navigation.routableDestinations) {
          expect(
            redirectFor(active(navigation.role), destination.path!),
            isNull,
            reason: '${destination.path} is ${navigation.role.name}\'s own',
          );
        }
      }
    });

    test('redirects the gate to the resolved role\'s landing path', () {
      for (final RoleNavigation navigation in RoleNavigationRegistry.ordered) {
        expect(
          redirectFor(active(navigation.role), AppRoutes.roleGate),
          navigation.landingPath,
        );
      }
    });

    test('holds an unresolved session on the gate', () {
      expect(
        redirectFor(const RoleSessionInitial(), AppRoutes.roleGate),
        isNull,
      );
      expect(
        redirectFor(const RoleSessionResolving(), AppRoutes.roleGate),
        isNull,
      );
    });

    test('never guards the access-denied route itself', () {
      // Guarding it would be a redirect loop: it is where the guard sends
      // people.
      for (final AppRole role in AppRole.values) {
        expect(redirectFor(active(role), AppRoutes.accessDenied), isNull);
      }
      expect(
        redirectFor(const RoleSessionInitial(), AppRoutes.accessDenied),
        isNull,
      );
    });
  });

  group('deep-linking into another role\'s group', () {
    /// Every wrong-role pairing, driven through the real router.
    for (final AppRole role in AppRole.values) {
      for (final RoleNavigation other in RoleNavigationRegistry.ordered) {
        if (other.role == role) continue;

        testWidgets('${role.displayName} cannot reach ${other.landingPath}', (
          tester,
        ) async {
          await pumpAppInRole(tester, role);

          final BuildContext context = tester.element(
            find.byType(Scaffold).first,
          );
          context.go(other.landingPath);
          await tester.pumpAndSettle();

          expect(find.byType(SrAccessDeniedView), findsOneWidget);

          // And no shell at all was built — not the target role's, and not
          // the caller's.
          expect(find.byType(VendorShell), findsNothing);
          expect(find.byType(RetailerOwnerShell), findsNothing);
          expect(find.byType(RetailerManagerShell), findsNothing);
          expect(find.byType(SalesStaffShell), findsNothing);
        });
      }
    }
  });
}
