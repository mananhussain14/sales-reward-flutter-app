import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/entities/app_role.dart';
import '../../features/auth/presentation/bloc/role_session_bloc.dart';
import '../../features/auth/presentation/pages/access_denied_page.dart';
import '../../features/auth/presentation/pages/role_gate_page.dart';
import '../../features/dashboard/presentation/retailer_owner/pages/retailer_owner_overview_page.dart';
import '../../features/dashboard/presentation/vendor/pages/vendor_dashboard_page.dart';
import '../../features/receipts/presentation/sales_staff/pages/sales_staff_submit_page.dart';
import '../../features/staff/presentation/retailer_manager/pages/retailer_manager_staff_page.dart';
import '../navigation/role_navigation_registry.dart';
import '../shells/base/placeholder_destination_page.dart';
import '../shells/retailer_manager/retailer_manager_navigation.dart';
import '../shells/retailer_manager/retailer_manager_shell.dart';
import '../shells/retailer_owner/retailer_owner_navigation.dart';
import '../shells/retailer_owner/retailer_owner_shell.dart';
import '../shells/sales_staff/sales_staff_navigation.dart';
import '../shells/sales_staff/sales_staff_shell.dart';
import '../shells/vendor/vendor_navigation.dart';
import '../shells/vendor/vendor_shell.dart';
import 'app_routes.dart';
import 'router_refresh.dart';

/// Builds the application router.
///
/// ## Four route groups, one per role
///
/// Each role owns a prefix — `/vendor`, `/retailer-owner`, `/retailer-manager`,
/// `/sales-staff` — and a `ShellRoute` that builds only that role's shell. The
/// groups do not overlap and no path is shared between them, which is what makes
/// "can a Sales Staff shell ever render a Vendor screen?" answerable by reading
/// one file.
///
/// ## The guard
///
/// [redirectFor] is a **presentation** guard. It keeps a user out of a shell
/// they do not belong in, which prevents a confusing screen — not a security
/// incident. Supabase remains the authorization authority: every read and write
/// behind these screens is decided again in SQL by a `SECURITY DEFINER` function
/// that derives the caller from `auth.uid()` and accepts no user id. If this
/// guard were deleted entirely, a user who typed another role's URL would reach
/// a shell whose every query returned `42501`.
///
/// It is written to fail closed: no resolved role sends the user back to the
/// gate, and a mismatched role sends them to the shared access-denied screen.
GoRouter buildAppRouter({
  required RoleSessionBloc roleSessionBloc,
  String initialLocation = AppRoutes.roleGate,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: GoRouterRefreshStream(roleSessionBloc.stream),
    redirect: (BuildContext context, GoRouterState state) =>
        redirectFor(roleSessionBloc.state, state.matchedLocation),
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.roleGate,
        builder: (BuildContext context, GoRouterState state) =>
            const RoleGatePage(),
      ),
      GoRoute(
        path: AppRoutes.accessDenied,
        builder: (BuildContext context, GoRouterState state) =>
            const AccessDeniedPage(),
      ),
      _vendorRoutes(roleSessionBloc),
      _retailerOwnerRoutes(roleSessionBloc),
      _retailerManagerRoutes(roleSessionBloc),
      _salesStaffRoutes(roleSessionBloc),
    ],
  );
}

/// The route guard, written as a pure function of (session state, location) so
/// it can be tested directly against a table of cases — the same discipline the
/// web repository applies to `landing-decision.ts` and
/// `portal-access-decision.ts`.
///
/// Returns the path to redirect to, or null to allow the navigation.
String? redirectFor(RoleSessionState session, String location) {
  // Always reachable. It is the destination of a denial, so guarding it would
  // be a redirect loop.
  if (location == AppRoutes.accessDenied) {
    return null;
  }

  final ResolvedRole? resolved = session.resolved;
  final AppRole? owningRole = RoleNavigationRegistry.roleOwning(location);

  if (owningRole == null) {
    // Not inside any role group — the gate, or an unknown path.
    if (location == AppRoutes.roleGate) {
      if (resolved != null) {
        return RoleNavigationRegistry.landingPathFor(resolved.role);
      }
      if (session is RoleSessionNoAccess) {
        return AppRoutes.accessDenied;
      }
    }
    return null;
  }

  // Inside a role group. Fail closed on both branches.
  if (resolved == null) {
    return AppRoutes.roleGate;
  }
  if (resolved.role != owningRole) {
    return AppRoutes.accessDenied;
  }
  return null;
}

/// Builds a role's `ShellRoute`.
///
/// [shellBuilder] is supplied per role rather than switched on inside one
/// builder, so no single function knows how to construct more than one shell.
ShellRoute _roleShell({
  required RoleSessionBloc bloc,
  required AppRole role,
  required Widget Function(Widget child, String location, ResolvedRole resolved)
  shellBuilder,
  required List<RouteBase> routes,
}) {
  return ShellRoute(
    builder: (BuildContext context, GoRouterState state, Widget child) {
      final ResolvedRole? resolved = bloc.state.resolved;

      // The guard should have redirected already. If it somehow did not, refuse
      // rather than inventing a role to render with.
      if (resolved == null || resolved.role != role) {
        return const AccessDeniedPage();
      }

      return shellBuilder(child, state.matchedLocation, resolved);
    },
    routes: routes,
  );
}

RouteBase _vendorRoutes(RoleSessionBloc bloc) {
  const String roleName = 'Vendor Super Admin';

  return _roleShell(
    bloc: bloc,
    role: AppRole.vendorSuperAdmin,
    shellBuilder: (Widget child, String location, ResolvedRole resolved) =>
        VendorShell(location: location, resolved: resolved, child: child),
    routes: <RouteBase>[
      GoRoute(
        path: VendorNavigation.dashboard,
        builder: (BuildContext context, GoRouterState state) =>
            const VendorDashboardPage(),
      ),
      GoRoute(
        path: VendorNavigation.retailers,
        builder: (BuildContext context, GoRouterState state) =>
            const PlaceholderDestinationPage(
              roleName: roleName,
              title: 'Retailers',
              backendNote:
                  'Needs list_vendor_retailers() and '
                  'get_vendor_retailer_detail(); both are proposed, neither '
                  'exists. Phase 3.',
            ),
      ),
      GoRoute(
        path: VendorNavigation.users,
        builder: (BuildContext context, GoRouterState state) =>
            const PlaceholderDestinationPage(
              roleName: roleName,
              title: 'Users',
              backendNote:
                  'Needs list_vendor_organization_members(); the web assembles '
                  'this from a four-query join in TypeScript today. Phase 3.',
            ),
      ),
      GoRoute(
        path: VendorNavigation.roles,
        builder: (BuildContext context, GoRouterState state) =>
            const PlaceholderDestinationPage(
              roleName: roleName,
              title: 'Roles',
              backendNote:
                  'The roles and permissions catalogue is readable through RLS '
                  'today; the screen is simply not built. Phase 3.',
            ),
      ),
      GoRoute(
        path: VendorNavigation.products,
        builder: (BuildContext context, GoRouterState state) =>
            const PlaceholderDestinationPage(
              roleName: roleName,
              title: 'Products',
              backendNote:
                  'list_vendor_products() and the create/update/status RPCs all '
                  'exist; the screens are not built. Phase 3.',
            ),
      ),
      GoRoute(
        path: VendorNavigation.auditLogs,
        builder: (BuildContext context, GoRouterState state) =>
            const PlaceholderDestinationPage(
              roleName: roleName,
              title: 'Audit logs',
              backendNote:
                  'Needs list_vendor_audit_logs(p_limit, p_before); the current '
                  'read is capped at 100 rows with no pagination. Phase 3.',
            ),
      ),
      GoRoute(
        path: VendorNavigation.profile,
        builder: (BuildContext context, GoRouterState state) =>
            const PlaceholderDestinationPage(
              roleName: roleName,
              title: 'Profile',
              backendNote:
                  'Needs an authenticated session. Authentication is not '
                  'implemented in this milestone.',
            ),
      ),
    ],
  );
}

RouteBase _retailerOwnerRoutes(RoleSessionBloc bloc) {
  const String roleName = 'Retailer Owner';

  return _roleShell(
    bloc: bloc,
    role: AppRole.retailerOwner,
    shellBuilder: (Widget child, String location, ResolvedRole resolved) =>
        RetailerOwnerShell(
          location: location,
          resolved: resolved,
          child: child,
        ),
    routes: <RouteBase>[
      GoRoute(
        path: RetailerOwnerNavigation.overview,
        builder: (BuildContext context, GoRouterState state) =>
            const RetailerOwnerOverviewPage(),
      ),
      GoRoute(
        path: RetailerOwnerNavigation.shops,
        builder: (BuildContext context, GoRouterState state) =>
            const PlaceholderDestinationPage(
              roleName: roleName,
              title: 'Shops',
              backendNote:
                  'list_retailer_owner_portal_shops() exists but returns no '
                  'shop_id, so a mobile list cannot key its rows or navigate to '
                  'a detail screen. Contract fix #1.',
            ),
      ),
      GoRoute(
        path: RetailerOwnerNavigation.staff,
        builder: (BuildContext context, GoRouterState state) =>
            const PlaceholderDestinationPage(
              roleName: roleName,
              title: 'Staff',
              backendNote:
                  'The roster and invitation reads exist. Sending an invitation '
                  'needs the send-staff-invitation Edge Function, which holds '
                  'the token and the Resend key. Phase 2.',
            ),
      ),
      GoRoute(
        path: RetailerOwnerNavigation.products,
        builder: (BuildContext context, GoRouterState state) =>
            const PlaceholderDestinationPage(
              roleName: roleName,
              title: 'Products',
              backendNote:
                  'list_retailer_assigned_products() is ready; the screen is '
                  'not built. Phase 2.',
            ),
      ),
      GoRoute(
        path: RetailerOwnerNavigation.profile,
        builder: (BuildContext context, GoRouterState state) =>
            const PlaceholderDestinationPage(
              roleName: roleName,
              title: 'Profile',
              backendNote:
                  'Needs an authenticated session. Authentication is not '
                  'implemented in this milestone.',
            ),
      ),
    ],
  );
}

RouteBase _retailerManagerRoutes(RoleSessionBloc bloc) {
  const String roleName = 'Retailer Manager';

  return _roleShell(
    bloc: bloc,
    role: AppRole.retailerManager,
    shellBuilder: (Widget child, String location, ResolvedRole resolved) =>
        RetailerManagerShell(
          location: location,
          resolved: resolved,
          child: child,
        ),
    routes: <RouteBase>[
      GoRoute(
        path: RetailerManagerNavigation.staff,
        builder: (BuildContext context, GoRouterState state) =>
            const RetailerManagerStaffPage(),
      ),
      GoRoute(
        path: RetailerManagerNavigation.products,
        builder: (BuildContext context, GoRouterState state) =>
            const PlaceholderDestinationPage(
              roleName: roleName,
              title: 'Products',
              backendNote:
                  'list_retailer_assigned_products() is ready; the screen is '
                  'not built. Phase 2.',
            ),
      ),
      GoRoute(
        path: RetailerManagerNavigation.profile,
        builder: (BuildContext context, GoRouterState state) =>
            const PlaceholderDestinationPage(
              roleName: roleName,
              title: 'Profile',
              backendNote:
                  'Needs an authenticated session. Authentication is not '
                  'implemented in this milestone.',
            ),
      ),
    ],
  );
}

RouteBase _salesStaffRoutes(RoleSessionBloc bloc) {
  const String roleName = 'Sales Staff';

  return _roleShell(
    bloc: bloc,
    role: AppRole.salesStaff,
    shellBuilder: (Widget child, String location, ResolvedRole resolved) =>
        SalesStaffShell(location: location, resolved: resolved, child: child),
    routes: <RouteBase>[
      GoRoute(
        path: SalesStaffNavigation.submit,
        builder: (BuildContext context, GoRouterState state) =>
            const SalesStaffSubmitPage(),
      ),
      GoRoute(
        path: SalesStaffNavigation.history,
        builder: (BuildContext context, GoRouterState state) =>
            const PlaceholderDestinationPage(
              roleName: roleName,
              title: 'My receipts',
              backendNote:
                  'list_my_receipt_submissions() is ready and scoped to '
                  'auth.uid() in SQL. Viewing a submitted image has no read '
                  'path anywhere in the backend — open question Q1.',
            ),
      ),
      GoRoute(
        path: SalesStaffNavigation.profile,
        builder: (BuildContext context, GoRouterState state) =>
            const PlaceholderDestinationPage(
              roleName: roleName,
              title: 'Profile',
              backendNote:
                  'Needs an authenticated session. Authentication is not '
                  'implemented in this milestone.',
            ),
      ),
    ],
  );
}
