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
/// groups do not overlap and no path is shared, which makes "can a Sales Staff
/// shell ever render a Vendor screen?" answerable by reading one file.
///
/// The web serves the Owner, Manager and Sales Staff from one `/retailer/*` tree
/// and separates them with server-side checks. Splitting them here does not
/// weaken that — it adds a second, purely presentational boundary on top of it.
///
/// ## The guard
///
/// [redirectFor] is a **presentation** guard. It keeps a user out of a shell
/// they do not belong in, which prevents a confusing screen — not a security
/// incident. Supabase remains the authorization authority: every read and write
/// behind these screens is decided again in SQL by a `SECURITY DEFINER` function
/// that derives the caller from `auth.uid()` and accepts no user id. The
/// role-flow map states the rule three times over; if this guard were deleted
/// entirely, a user who typed another role's URL would reach a shell whose every
/// query returned `42501`.
///
/// It is written to fail closed: no resolved role sends the user back to the
/// gate, and a mismatched role sends them to the shared access-denied screen.
///
/// ## Lazy construction
///
/// Every route builds its page in a closure, so a screen is constructed only
/// when it is actually visited. Nothing is instantiated at router-build time.
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
/// it can be tested against a table of cases — the discipline the web repository
/// applies to `landing-decision.ts` and `portal-access-decision.ts`.
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

/// A placeholder route, so the ten unbuilt destinations read identically.
GoRoute _placeholder({
  required String path,
  required String roleName,
  required String title,
  required String backendNote,
}) {
  return GoRoute(
    path: path,
    builder: (BuildContext context, GoRouterState state) =>
        PlaceholderDestinationPage(
          roleName: roleName,
          title: title,
          backendNote: backendNote,
        ),
  );
}

RouteBase _vendorRoutes(RoleSessionBloc bloc) {
  const String role = 'Vendor Super Admin';

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
      _placeholder(
        path: VendorNavigation.retailers,
        roleName: role,
        title: 'Retailers',
        backendNote:
            'V-05 and V-06. Needs list_vendor_retailers() and '
            'get_vendor_retailer_detail(); the current reads fetch every shop '
            'row just to count them. Phase 3.',
      ),
      _placeholder(
        path: VendorNavigation.users,
        roleName: role,
        title: 'Users',
        backendNote:
            'V-02. Needs list_vendor_organization_members(); the web assembles '
            'this from a four-query join in TypeScript, which Flutter must not '
            're-implement. Phase 3.',
      ),
      _placeholder(
        path: VendorNavigation.roles,
        roleName: role,
        title: 'Roles',
        backendNote:
            'V-03. The roles and permissions catalogue is readable through RLS '
            'today for a Vendor; only the screen is missing. Phase 3.',
      ),
      _placeholder(
        path: VendorNavigation.products,
        roleName: role,
        title: 'Products',
        backendNote:
            'V-12 to V-16. The RPCs exist. Duplicate code-vs-barcode errors are '
            'discriminated by an English message substring today — Flutter must '
            'not re-implement that matching (contract fix #3). Phase 3.',
      ),
      _placeholder(
        path: VendorNavigation.auditLogs,
        roleName: role,
        title: 'Audit Logs',
        backendNote:
            'V-04. Needs list_vendor_audit_logs(p_limit, p_before); the current '
            'read is a fixed 100 rows with no pagination. Phase 3.',
      ),
    ],
  );
}

RouteBase _retailerOwnerRoutes(RoleSessionBloc bloc) {
  const String role = 'Retailer Owner';

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
      _placeholder(
        path: RetailerOwnerNavigation.shops,
        roleName: role,
        title: 'Shops',
        backendNote:
            'RO-02. list_retailer_owner_portal_shops() exists but returns no '
            'shop_id, so a list cannot key its rows or open a detail screen. '
            'Render non-tappable until contract fix #1.',
      ),
      _placeholder(
        path: RetailerOwnerNavigation.staff,
        roleName: role,
        title: 'Staff',
        backendNote:
            'RO-04 to RO-09. The roster, invitation and revoke paths are ready. '
            'Sending an invitation needs the send-staff-invitation Edge '
            'Function, which holds the token and the Resend key. Phase 2.',
      ),
      _placeholder(
        path: RetailerOwnerNavigation.products,
        roleName: role,
        title: 'Products',
        backendNote:
            'RO-03. list_retailer_assigned_products() is ready and identical '
            'for the Owner and the Manager; only the screen is missing. '
            'Phase 2.',
      ),
    ],
  );
}

RouteBase _retailerManagerRoutes(RoleSessionBloc bloc) {
  const String role = 'Retailer Manager';

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
      _placeholder(
        path: RetailerManagerNavigation.products,
        roleName: role,
        title: 'Products',
        backendNote:
            'RM-03. list_retailer_assigned_products() is ready and this role '
            'is permitted to read it. Only the screen is missing. Phase 2.',
      ),
    ],
  );
}

RouteBase _salesStaffRoutes(RoleSessionBloc bloc) {
  const String role = 'Sales Staff';

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
      _placeholder(
        path: SalesStaffNavigation.history,
        roleName: role,
        title: 'My receipts',
        backendNote:
            'SS-05 is ready — list_my_receipt_submissions() is scoped to '
            'auth.uid() in SQL. SS-06 is not: there is no read path anywhere in '
            'the backend for a submitted image, so a row cannot be opened '
            '(Q1 / D-5).',
      ),
    ],
  );
}
