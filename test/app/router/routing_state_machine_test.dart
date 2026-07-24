import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/app/navigation/role_navigation_registry.dart';
import 'package:sale_reward/app/router/app_router.dart';
import 'package:sale_reward/app/router/app_routes.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/auth/presentation/bloc/session_bloc.dart';

import '../../support/fakes.dart';

/// The routing state machine, tested as the pure function it is.
///
/// `redirectFor` decides every redirect the app can perform, so pinning it
/// against a table is the cheapest way to guarantee that no session state can
/// reach a screen it does not belong at — and that no user can reach another
/// role's shell by typing a URL.
void main() {
  SessionState active(PortalKind kind) => SessionActive(contextFor(kind));

  String landing(PortalKind kind) =>
      RoleNavigationRegistry.landingPathFor(kind)!;

  const List<PortalKind> shellKinds = <PortalKind>[
    PortalKind.vendorSuperAdmin,
    PortalKind.retailerOwner,
    PortalKind.retailerManager,
    PortalKind.salesStaff,
  ];

  group('sessionHome', () {
    test('maps each state to its single home', () {
      expect(sessionHome(const SessionInitial()), AppRoutes.splash);
      expect(sessionHome(const SessionResolving()), AppRoutes.splash);
      expect(sessionHome(const SessionUnauthenticated()), AppRoutes.login);
      expect(sessionHome(const SessionDenied()), AppRoutes.accessDenied);
      expect(
        sessionHome(const SessionUnavailable(UnavailableFailure())),
        AppRoutes.unavailable,
      );
      for (final PortalKind kind in shellKinds) {
        expect(sessionHome(active(kind)), landing(kind));
      }
    });
  });

  group('no shell before resolution', () {
    test('every role route redirects to the splash while indeterminate', () {
      for (final PortalKind kind in shellKinds) {
        final String path = landing(kind);
        expect(redirectFor(const SessionInitial(), path), AppRoutes.splash);
        expect(redirectFor(const SessionResolving(), path), AppRoutes.splash);
      }
    });
  });

  group('unauthenticated', () {
    test('any role route redirects to login', () {
      for (final PortalKind kind in shellKinds) {
        expect(
          redirectFor(const SessionUnauthenticated(), landing(kind)),
          AppRoutes.login,
        );
      }
    });

    test('the login route itself is allowed', () {
      expect(
        redirectFor(const SessionUnauthenticated(), AppRoutes.login),
        isNull,
      );
    });
  });

  group('active roles reach only their own shell', () {
    test('each role is allowed within its own group', () {
      for (final PortalKind kind in shellKinds) {
        expect(redirectFor(active(kind), landing(kind)), isNull);
      }
    });

    test('a role in another group is redirected to its own landing', () {
      for (final PortalKind kind in shellKinds) {
        for (final PortalKind other in shellKinds) {
          if (other == kind) continue;
          expect(
            redirectFor(active(kind), landing(other)),
            landing(kind),
            reason: '${kind.name} must not reach ${other.name}',
          );
        }
      }
    });

    test('an active role at login or splash is sent to its landing', () {
      for (final PortalKind kind in shellKinds) {
        expect(redirectFor(active(kind), AppRoutes.login), landing(kind));
        expect(redirectFor(active(kind), AppRoutes.splash), landing(kind));
      }
    });
  });

  group('denied', () {
    test('lands on access-denied and is redirected there from elsewhere', () {
      expect(
        redirectFor(const SessionDenied(), AppRoutes.accessDenied),
        isNull,
      );
      expect(
        redirectFor(const SessionDenied(), landing(PortalKind.salesStaff)),
        AppRoutes.accessDenied,
      );
      expect(
        redirectFor(const SessionDenied(), AppRoutes.login),
        AppRoutes.accessDenied,
      );
    });
  });

  group('unavailable', () {
    const SessionState unavailable = SessionUnavailable(UnavailableFailure());

    test('lands on the retry screen, never on access-denied', () {
      expect(redirectFor(unavailable, AppRoutes.unavailable), isNull);
      expect(
        redirectFor(unavailable, landing(PortalKind.vendorSuperAdmin)),
        AppRoutes.unavailable,
      );
      // The distinction that matters most: a failure is not a denial.
      expect(
        redirectFor(unavailable, AppRoutes.accessDenied),
        AppRoutes.unavailable,
      );
    });
  });
}
