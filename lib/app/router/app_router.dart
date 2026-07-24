import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/entities/portal_context.dart';
import '../../features/auth/domain/entities/portal_kind.dart';
import '../../features/auth/presentation/bloc/session_bloc.dart';
import '../../features/auth/presentation/pages/access_denied_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/splash_page.dart';
import '../../features/auth/presentation/pages/unavailable_page.dart';
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
/// ## The routing state machine
///
/// [redirectFor] is the whole of it: a **pure function** of the session state
/// and the requested location, tested against a table of cases. Every redirect
/// the app can perform is decided here, which is what makes "can a Sales Staff
/// user reach the Vendor shell?" answerable by reading one function.
///
/// | Session state | Home |
/// | --- | --- |
/// | initial / resolving | `/` (splash) — nothing else may render yet |
/// | unauthenticated | `/login` |
/// | active(kind) | that kind's landing path |
/// | denied (NONE) | `/access-denied` |
/// | unavailable | `/unavailable` |
///
/// A request for any location other than the caller's home is redirected to it,
/// with one exception: an **active** caller may move freely *within their own
/// role group*, so tab navigation works. A request into another role's group is
/// sent back to the caller's own landing — a user cannot reach another shell by
/// typing a URL.
///
/// ## No shell before resolution
///
/// While the session is indeterminate every role route redirects to the splash,
/// so no authenticated shell can flash before the backend has answered.
///
/// ## The guard is presentation, not security
///
/// Supabase remains the authorization authority: every read and write behind
/// these screens is decided again in SQL by a `SECURITY DEFINER` function that
/// derives the caller from `auth.uid()`. If this guard were deleted, a user who
/// typed another role's URL would reach a shell whose every query returned a
/// refusal — the guard prevents a confusing screen, not a breach.
GoRouter buildAppRouter({
  required SessionBloc sessionBloc,
  String initialLocation = AppRoutes.splash,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: GoRouterRefreshStream(sessionBloc.stream),
    redirect: (BuildContext context, GoRouterState state) =>
        redirectFor(sessionBloc.state, state.matchedLocation),
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.splash,
        builder: (BuildContext context, GoRouterState state) =>
            const SplashPage(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (BuildContext context, GoRouterState state) =>
            const LoginPage(),
      ),
      GoRoute(
        path: AppRoutes.accessDenied,
        builder: (BuildContext context, GoRouterState state) =>
            const AccessDeniedPage(),
      ),
      GoRoute(
        path: AppRoutes.unavailable,
        builder: (BuildContext context, GoRouterState state) =>
            const UnavailablePage(),
      ),
      _vendorRoutes(sessionBloc),
      _retailerOwnerRoutes(sessionBloc),
      _retailerManagerRoutes(sessionBloc),
      _salesStaffRoutes(sessionBloc),
    ],
  );
}

/// The single location this session state belongs at.
///
/// Exposed for tests: the redirect table is easier to reason about when the
/// "home" of each state is named directly.
String sessionHome(SessionState session) {
  return switch (session) {
    SessionInitial() || SessionResolving() => AppRoutes.splash,
    SessionUnauthenticated() => AppRoutes.login,
    SessionDenied() => AppRoutes.accessDenied,
    SessionUnavailable() => AppRoutes.unavailable,
    SessionActive(:final PortalContext portalContext) =>
      RoleNavigationRegistry.landingPathFor(portalContext.portalKind) ??
          AppRoutes.accessDenied,
  };
}

/// The route guard. Returns the path to redirect to, or null to allow.
String? redirectFor(SessionState session, String location) {
  final String home = sessionHome(session);

  // An active caller may roam freely inside their OWN role group so that tab
  // navigation and deep links within it work. Anything else — another group,
  // the login screen, the splash — goes to their landing.
  if (session is SessionActive) {
    final PortalKind kind = session.portalContext.portalKind;
    final PortalKind? owningRole = RoleNavigationRegistry.roleOwning(location);
    if (owningRole != null && owningRole == kind) {
      return null;
    }
    return location == home ? null : home;
  }

  // Every non-active state has exactly one permitted location.
  return location == home ? null : home;
}

/// Builds a role's `ShellRoute`.
///
/// [shellBuilder] is supplied per role rather than switched on inside one
/// builder, so no single function knows how to construct more than one shell.
ShellRoute _roleShell({
  required SessionBloc bloc,
  required PortalKind role,
  required Widget Function(Widget child, String location, PortalContext context)
  shellBuilder,
  required List<RouteBase> routes,
}) {
  return ShellRoute(
    builder: (BuildContext context, GoRouterState state, Widget child) {
      final SessionState session = bloc.state;

      // The guard should have redirected already. If it somehow did not, refuse
      // rather than invent a context to render with.
      if (session is! SessionActive ||
          session.portalContext.portalKind != role) {
        return const AccessDeniedPage();
      }
      return shellBuilder(child, state.matchedLocation, session.portalContext);
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

RouteBase _vendorRoutes(SessionBloc bloc) {
  const String role = 'Vendor Super Admin';

  return _roleShell(
    bloc: bloc,
    role: PortalKind.vendorSuperAdmin,
    shellBuilder: (Widget child, String location, PortalContext context) =>
        VendorShell(location: location, portalContext: context, child: child),
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

RouteBase _retailerOwnerRoutes(SessionBloc bloc) {
  const String role = 'Retailer Owner';

  return _roleShell(
    bloc: bloc,
    role: PortalKind.retailerOwner,
    shellBuilder: (Widget child, String location, PortalContext context) =>
        RetailerOwnerShell(
          location: location,
          portalContext: context,
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

RouteBase _retailerManagerRoutes(SessionBloc bloc) {
  const String role = 'Retailer Manager';

  return _roleShell(
    bloc: bloc,
    role: PortalKind.retailerManager,
    shellBuilder: (Widget child, String location, PortalContext context) =>
        RetailerManagerShell(
          location: location,
          portalContext: context,
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

RouteBase _salesStaffRoutes(SessionBloc bloc) {
  const String role = 'Sales Staff';

  return _roleShell(
    bloc: bloc,
    role: PortalKind.salesStaff,
    shellBuilder: (Widget child, String location, PortalContext context) =>
        SalesStaffShell(
          location: location,
          portalContext: context,
          child: child,
        ),
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
