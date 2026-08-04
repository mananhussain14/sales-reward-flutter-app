import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../features/audit/presentation/vendor/pages/vendor_audit_logs_page.dart';
import '../../features/auth/domain/entities/portal_context.dart';
import '../../features/auth/domain/entities/portal_kind.dart';
import '../../features/auth/presentation/bloc/session_bloc.dart';
import '../../features/auth/presentation/pages/access_denied_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/splash_page.dart';
import '../../features/auth/presentation/pages/unavailable_page.dart';
import '../../features/campaigns/presentation/retailer_owner/pages/retailer_owner_campaign_detail_page.dart';
import '../../features/campaigns/presentation/retailer_owner/pages/retailer_owner_campaigns_page.dart';
import '../../features/campaigns/presentation/sales_staff/pages/sales_staff_campaign_detail_page.dart';
import '../../features/campaigns/presentation/sales_staff/pages/sales_staff_campaigns_page.dart';
import '../../features/dashboard/presentation/retailer_owner/pages/retailer_owner_overview_page.dart';
import '../../features/dashboard/presentation/vendor/pages/vendor_dashboard_page.dart';
import '../../features/products/presentation/retailer/pages/retailer_products_page.dart';
import '../../features/products/presentation/vendor/pages/vendor_product_create_page.dart';
import '../../features/products/presentation/vendor/pages/vendor_product_detail_page.dart';
import '../../features/products/presentation/vendor/pages/vendor_product_edit_page.dart';
import '../../features/products/presentation/vendor/pages/vendor_products_page.dart';
import '../../features/profile/presentation/vendor/pages/vendor_company_profile_page.dart';
import '../../features/receipts/domain/repositories/receipt_extraction_repository.dart';
import '../../features/receipts/domain/repositories/receipt_repository.dart';
import '../../features/receipts/presentation/sales_staff/cubit/receipt_product_selection_cubit.dart';
import '../../features/receipts/presentation/sales_staff/cubit/receipt_review_cubit.dart';
import '../../features/receipts/presentation/sales_staff/pages/sales_staff_history_page.dart';
import '../../features/receipts/presentation/sales_staff/pages/sales_staff_receipt_review_page.dart';
import '../../features/receipts/presentation/sales_staff/pages/sales_staff_submit_page.dart';
import '../../features/retailers/presentation/vendor/pages/vendor_retailer_detail_page.dart';
import '../../features/retailers/presentation/vendor/pages/vendor_retailers_page.dart';
import '../../features/roles/presentation/vendor/pages/vendor_role_detail_page.dart';
import '../../features/roles/presentation/vendor/pages/vendor_roles_page.dart';
import '../../features/shops/presentation/retailer_owner/pages/retailer_owner_shops_page.dart';
import '../../features/staff/presentation/retailer/pages/retailer_staff_page.dart';
import '../../features/users/presentation/vendor/pages/vendor_user_detail_page.dart';
import '../../features/users/presentation/vendor/pages/vendor_users_page.dart';
import '../navigation/role_navigation_registry.dart';
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

// The `_placeholder` helper is gone: every route in every shell now builds a
// real, backend-backed page. `PlaceholderDestinationPage` itself is kept — the
// Vendor navigation still carries "Soon" entries that have no route at all, and
// three flow tests assert it never appears on a built screen.

RouteBase _vendorRoutes(SessionBloc bloc) {
  // Every Vendor destination that has a route now has a real page. The remaining
  // five are "Soon" entries in the navigation model and have no route at all, so
  // there is no placeholder page left to name a role for here.
  return _roleShell(
    bloc: bloc,
    role: PortalKind.vendorSuperAdmin,
    shellBuilder: (Widget child, String location, PortalContext context) =>
        VendorShell(location: location, portalContext: context, child: child),
    routes: <RouteBase>[
      // V-01. Backed by get_vendor_admin_dashboard_summary(), which takes ZERO
      // arguments — no identity, tenant, organization, role, permission, status
      // or date range — and derives the Vendor from auth.uid() in SQL, applying
      // the same lowest-organization-id tie-break every other Vendor RPC applies.
      // It requires Vendor Super Admin authority AND all three of the read
      // permissions its four counted relations already require, and refuses the
      // whole summary with one generic 42501 when any is missing.
      //
      // READ-ONLY, and there is no detail route: the contract returns four
      // scalars and nothing addressable, so no figure on this screen holds an
      // address for anything. The organization NAME on the page comes from the
      // trusted session context this shell already carries — never from the
      // summary, and never from a direct read of `organizations`.
      //
      // NOT nested, like the Audit Logs route — there is nothing to nest.
      // `indexForLocation` keeps the Dashboard destination selected on this path.
      GoRoute(
        path: VendorNavigation.dashboard,
        builder: (BuildContext context, GoRouterState state) =>
            const VendorDashboardPage(),
      ),
      // V-05 and V-06. Backed by list_vendor_retailers(),
      // get_vendor_retailer_detail(uuid) and list_vendor_retailer_shops(uuid),
      // all three of which derive the Vendor from auth.uid() and accept no
      // identity or tenant argument.
      //
      // The detail route is NESTED rather than declared alongside, so a `go`
      // into it stacks the directory beneath — the back gesture returns to a
      // list that is still loaded, because the cubit holding it belongs to the
      // shell above both.
      GoRoute(
        path: VendorNavigation.retailers,
        builder: (BuildContext context, GoRouterState state) =>
            const VendorRetailersPage(),
        routes: <RouteBase>[
          GoRoute(
            path: VendorNavigation.retailerDetailSegment,
            builder: (BuildContext context, GoRouterState state) =>
                VendorRetailerDetailPage(
                  // Passed through verbatim. A malformed value is not rejected
                  // here: the repository answers exactly as the backend answers
                  // for an id that names no row, so a mistyped URL, an unknown
                  // id and another Vendor's id all reach one non-leaking state.
                  relationshipId: state.pathParameters['relationshipId'] ?? '',
                ),
          ),
        ],
      ),
      // V-02. Backed by list_vendor_users() and get_vendor_user_detail(uuid),
      // both of which derive the Vendor from auth.uid() and accept no identity
      // or tenant argument. The four-table join the web performs in TypeScript
      // happens in SQL, so Flutter does not re-implement it.
      //
      // Nested for the same reason the Retailer detail is: a `go` into it stacks
      // the directory beneath, so browser back returns to a list that is still
      // loaded.
      GoRoute(
        path: VendorNavigation.users,
        builder: (BuildContext context, GoRouterState state) =>
            const VendorUsersPage(),
        routes: <RouteBase>[
          GoRoute(
            path: VendorNavigation.userDetailSegment,
            builder: (BuildContext context, GoRouterState state) =>
                VendorUserDetailPage(
                  // Passed through verbatim. A malformed value is not rejected
                  // here: the repository answers exactly as the backend answers
                  // for an id that names no row, so a mistyped URL, an unknown
                  // id, another Vendor's id and a Retailer's membership id all
                  // reach one non-leaking state.
                  membershipId: state.pathParameters['membershipId'] ?? '',
                ),
          ),
        ],
      ),
      // V-03. Backed by list_vendor_roles(), get_vendor_role_detail(uuid) and
      // list_vendor_role_permissions(uuid). The first takes no arguments at all;
      // the other two take the opaque roles.id and nothing beside it, and all
      // three derive the Vendor from auth.uid() in SQL.
      //
      // The catalogue those reads return is GLOBAL — roles, permissions and
      // role_permissions carry no organization_id — so this route shows the same
      // definitions to every authorized Vendor, exactly as the web /roles page
      // does. The one tenant-scoped value is the assigned member count on each
      // row, which is why the Roles cubits are cleared by the shell's session
      // isolation like every other piece of private Vendor data.
      //
      // Nested for the same reason the other two details are: a `go` into it
      // stacks the catalogue beneath, so browser back returns to a list that is
      // still loaded.
      GoRoute(
        path: VendorNavigation.roles,
        builder: (BuildContext context, GoRouterState state) =>
            const VendorRolesPage(),
        routes: <RouteBase>[
          GoRoute(
            path: VendorNavigation.roleDetailSegment,
            builder: (BuildContext context, GoRouterState state) =>
                VendorRoleDetailPage(
                  // Passed through verbatim. A malformed value is not rejected
                  // here: the repository answers exactly as the backend answers
                  // for an id that names no role — without issuing a request —
                  // so a mistyped URL and an unknown id reach one non-leaking
                  // state.
                  roleId: state.pathParameters['roleId'] ?? '',
                ),
          ),
        ],
      ),
      // V-12, V-12a, V-16a, V-13 and V-14. Backed by list_vendor_products(),
      // get_vendor_product_detail(uuid),
      // list_vendor_product_assigned_retailers(uuid),
      // create_vendor_product(text, text, text, text, text),
      // update_vendor_product(uuid, text, text, text, text) and
      // set_vendor_product_status(uuid, text).
      //
      // Every one of the six derives the Vendor from auth.uid() through
      // get_vendor_super_admin_context() and accepts NO organization, tenant,
      // auth-user, profile, membership, actor, role, permission or audit-metadata
      // argument — there is no parameter for one. The reads take nothing or one
      // opaque vendor_products.id; the writes take product fields plus, for two of
      // them, that same id. Every id is matched on BOTH its own value and the
      // derived Vendor, so a foreign id selects nothing and is refused identically
      // to "you are not authorized".
      //
      // The three writes are gated on a DIFFERENT permission from the reads, which
      // is enforced entirely in SQL: this client neither knows, sends nor displays
      // either code, and both refusals arrive as one generic denial. The route
      // guard below is a presentation guard only.
      //
      // create_vendor_product takes no initial status (a new product is ACTIVE,
      // decided by the function) and update_vendor_product takes neither the
      // product code (immutable, and enforced by a trigger as well) nor the status.
      // A status change is set_vendor_product_status alone.
      //
      // NO ASSIGNMENT WRITE. V-16 (assign/withdraw) exists on a separate permission
      // and is a separate milestone; neither RPC is named anywhere in this
      // application, and the assigned-Retailer section stays read-only. Product
      // create, edit and status touch no assignment row — not even its updated_at.
      //
      // NO DELETE, anywhere: no control, no action, no RPC, and no DELETE statement
      // exists in the schema.
      //
      // An assignment row cross-links to the Retailer detail route above using
      // `relationship_id` — the same vendor_retailers.id those screens already
      // accept, which is why the assignment contract returns it. A null
      // relationship_id is a real state and is simply not navigable.
      //
      // Nested for the same reason the other three details are: a `go` into any of
      // them stacks the catalogue beneath, so browser back returns to a list that
      // is still loaded.
      GoRoute(
        path: VendorNavigation.products,
        builder: (BuildContext context, GoRouterState state) =>
            const VendorProductsPage(),
        routes: <RouteBase>[
          // DECLARED BEFORE the `:productId` route, and the order is load-bearing.
          // go_router matches in declaration order, so with these two reversed
          // `/vendor/products/new` would bind `productId = 'new'` and open the
          // detail screen for a product id that is not a uuid — reaching the
          // non-leaking "not available" state instead of the create form. `new` is
          // safe as a literal segment precisely because it can never be a uuid, so
          // no real product id can be shadowed by it.
          GoRoute(
            path: 'new',
            builder: (BuildContext context, GoRouterState state) =>
                const VendorProductCreatePage(),
          ),
          GoRoute(
            path: VendorNavigation.productDetailSegment,
            builder: (BuildContext context, GoRouterState state) =>
                VendorProductDetailPage(
                  // Passed through verbatim. A malformed value is not rejected
                  // here: the repository answers exactly as the backend answers
                  // for an id that names no product — without issuing a
                  // request — so a mistyped URL, an unknown id and another
                  // Vendor's id all reach one non-leaking state.
                  productId: state.pathParameters['productId'] ?? '',
                ),
            routes: <RouteBase>[
              GoRoute(
                path: VendorNavigation.productEditSegment,
                builder: (BuildContext context, GoRouterState state) =>
                    VendorProductEditPage(
                      // An ADDRESS and never form data. The screen fills its form
                      // from get_vendor_product_detail, so nothing in this URL can
                      // become a value that is saved back; and a malformed id
                      // reaches the same "not available" state, with no form and
                      // therefore no reachable write.
                      productId: state.pathParameters['productId'] ?? '',
                    ),
              ),
            ],
          ),
        ],
      ),
      // V-04. Backed by list_vendor_audit_logs(p_limit, p_before_occurred_at,
      // p_before_audit_log_id), which derives the Vendor from auth.uid() and
      // accepts no identity, tenant, role, permission, actor, entity, offset or
      // page argument — only a page size and a two-part keyset cursor taken from
      // a row the backend itself returned.
      //
      // READ-ONLY, and there is no detail route: no audit detail read exists on
      // the backend, because the web exposes no detail surface to share, and the
      // only thing one could add over the list is precisely what the contract
      // withholds — `metadata`, `entity_id`, `ip_address`, `user_agent`. There
      // is no entity or actor navigation either: neither id is returned, so no
      // row on this screen holds an address for anything.
      //
      // NOT nested, unlike the other four Vendor sections — there is nothing to
      // nest. `indexForLocation` still keeps the Audit Logs destination selected
      // on this exact path.
      GoRoute(
        path: VendorNavigation.auditLogs,
        builder: (BuildContext context, GoRouterState state) =>
            const VendorAuditLogsPage(),
      ),
      // The Vendor company and administrator profile, on the Settings
      // destination — which was a "Soon" placeholder until this milestone and now
      // has a route. Backed by get_my_vendor_profile(), which takes ZERO
      // arguments — no auth user id, profile id, membership id, organization id,
      // tenant id, role selector, permission selector, profile selector,
      // organization selector, status or date range — and derives BOTH the person
      // (from auth.uid()) and the Vendor (through get_vendor_super_admin_context()
      // with the usual lowest-organization-id tie-break) in SQL. It requires
      // Vendor Super Admin authority AND RBAC_READ, and refuses with one generic
      // 42501 when either is missing.
      //
      // TWO SOURCES, COMPOSED HERE. The administrator's display name and active
      // role names come from that RPC and from nowhere else; the Vendor
      // organization NAME comes from the trusted session context this shell
      // already carries — never from the RPC, which deliberately does not return
      // it, and never from a direct read of `organizations`.
      //
      // READ-ONLY, and there is no detail route: neither half is addressable, so
      // nothing on this screen holds an address for anything. There is no company
      // edit, profile edit, avatar upload, password screen or organization
      // switcher — none of them exists anywhere in this product, web or mobile.
      //
      // NOT nested, like the Dashboard and Audit Logs routes — there is nothing
      // to nest. `indexForLocation` keeps the Settings destination selected on
      // this exact path.
      GoRoute(
        path: VendorNavigation.settings,
        builder: (BuildContext context, GoRouterState state) =>
            const VendorCompanyProfilePage(),
      ),
    ],
  );
}

RouteBase _retailerOwnerRoutes(SessionBloc bloc) {
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
      // RO-02. Backed by list_retailer_owner_portal_shops(), which takes ZERO
      // arguments and scopes itself with
      // `resolve_retailer_owner_organization('RETAILER_SHOPS_READ')`.
      //
      // READ-ONLY and NOT NESTED, because there is nothing to nest: the contract
      // returns no shop_id, so no row on this screen holds an address for
      // anything and no detail route can exist. The list is deliberately
      // non-tappable — see RetailerShopCard for why not even a disabled
      // affordance is offered.
      //
      // Owner-only, and the Manager shell has no equivalent route. That function
      // does not raise for an unauthorized caller; it returns an empty list, so
      // a Manager would see an empty estate indistinguishable from a Retailer
      // that genuinely has none.
      GoRoute(
        path: RetailerOwnerNavigation.shops,
        builder: (BuildContext context, GoRouterState state) =>
            const RetailerOwnerShopsPage(),
      ),
      // RO-04. Backed by list_retailer_staff_members() and, for this role only,
      // list_retailer_staff_invitations(). Both take ZERO arguments and resolve
      // through resolve_retailer_member_organization on RETAILER_STAFF_READ and
      // RETAILER_STAFF_MANAGE respectively.
      //
      // READ-ONLY. There is no invite, resend, revoke, role change, activation
      // or shop-assignment control on this screen, and no write RPC is named
      // anywhere in this application. Sending an invitation additionally needs
      // the send-staff-invitation Edge Function, which holds the delivery
      // credential and is never called here.
      GoRoute(
        path: RetailerOwnerNavigation.staff,
        builder: (BuildContext context, GoRouterState state) =>
            const RetailerStaffPage(role: PortalKind.retailerOwner),
      ),
      // RO-03. Backed by list_retailer_assigned_products(), which takes ZERO
      // arguments — no Retailer, no Vendor, no product, no status — and returns
      // only rows whose assignment AND product are both ACTIVE.
      //
      // READ-ONLY, and the Retailer could not write here even if a control
      // existed: assignment is gated on PRODUCT_RETAILER_ASSIGN, a Vendor
      // capability, and neither assign RPC is named in the Retailer portal.
      // Identical contract for the Manager, which is why both shells route to
      // the same page.
      GoRoute(
        path: RetailerOwnerNavigation.products,
        builder: (BuildContext context, GoRouterState state) =>
            const RetailerProductsPage(role: PortalKind.retailerOwner),
      ),
      // RO-05. Backed by list_my_retailer_campaigns(), which takes ZERO
      // arguments and resolves through
      // resolve_retailer_member_organization('CAMPAIGNS_VIEW_ASSIGNED') — a
      // permission mapped to RETAILER_OWNER alone, which is why there is no
      // Manager equivalent below.
      //
      // READ-ONLY. There is no create, edit, publish, pause, resume, version or
      // cancel control on either of these screens, and no campaign write RPC is
      // named anywhere in this application: all of them are gated on
      // CAMPAIGNS_MANAGE, a Vendor capability exercised on the Web.
      GoRoute(
        path: RetailerOwnerNavigation.campaigns,
        builder: (BuildContext context, GoRouterState state) =>
            const RetailerOwnerCampaignsPage(),
        routes: <RouteBase>[
          // Nested, so the Campaigns destination stays selected while one
          // campaign is open and Back has a list to return to.
          //
          // The id is taken from the path and passed through unvalidated. That
          // is deliberate: the repository refuses a malformed id locally and
          // answers exactly as the backend answers for an id that names no
          // readable campaign, so a mistyped address and another Retailer's
          // campaign reach the identical screen. The check that matters is
          // get_my_retailer_campaign()'s own — it re-derives the Retailer from
          // auth.uid() and returns zero rows — not anything on the device.
          GoRoute(
            path: RetailerOwnerNavigation.campaignDetailSegment,
            builder: (BuildContext context, GoRouterState state) =>
                RetailerOwnerCampaignDetailPage(
                  campaignId: state.pathParameters['campaignId'] ?? '',
                ),
          ),
        ],
      ),
    ],
  );
}

RouteBase _retailerManagerRoutes(SessionBloc bloc) {
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
      // RM-01. The same page and the same roster RPC as the Owner's Staff
      // screen — the narrowing to ACTIVE members happens in SQL, through
      // `and (v_can_manage or m.status = 'ACTIVE')`, and this client applies no
      // equivalent filter.
      //
      // The invitation history is absent for this role, and the shell's cubit is
      // constructed with `includeInvitations: false` so the RPC is not called.
      // That is not the client enforcing a permission: the function resolves
      // through RETAILER_STAFF_MANAGE and would raise 42501 for a Manager
      // regardless. Not calling it avoids putting a denial notice on a screen
      // where nothing is wrong.
      //
      // There is NO Shops route and NO Overview route for this role. Both
      // backend contracts resolve through the Owner-only resolver, so both would
      // be permanently empty screens.
      GoRoute(
        path: RetailerManagerNavigation.staff,
        builder: (BuildContext context, GoRouterState state) =>
            const RetailerStaffPage(role: PortalKind.retailerManager),
      ),
      // RM-03. Identical contract to the Owner's Products screen — the same
      // member resolver on the same RETAILER_PRODUCTS_READ permission — which is
      // why both shells route to the same page.
      GoRoute(
        path: RetailerManagerNavigation.products,
        builder: (BuildContext context, GoRouterState state) =>
            const RetailerProductsPage(role: PortalKind.retailerManager),
      ),
    ],
  );
}

RouteBase _salesStaffRoutes(SessionBloc bloc) {
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
      // SS-05. list_my_receipt_submissions() is scoped to auth.uid() in SQL and
      // needs no argument.
      GoRoute(
        path: SalesStaffNavigation.history,
        builder: (BuildContext context, GoRouterState state) =>
            const SalesStaffHistoryPage(),
        routes: <RouteBase>[
          // SS-06. The receipt review, and the first route in this role that
          // carries an id.
          //
          // The id is taken from the path and shape-checked here, so a typed or
          // tampered address produces this screen's own refusal rather than a
          // PostgREST cast error. That check is NOT authorization: whether the
          // receipt is this person's is decided by
          // assert_my_receipt_extraction_access under their own token, and by
          // nothing on the device. A well-formed id belonging to somebody else
          // reaches the same refusal.
          //
          // The cubit is created HERE rather than in the shell, which is what
          // bounds the polling loop to this route: leaving the screen closes
          // the cubit, and closing it is what stops the loop and drops the
          // short-lived image capability.
          GoRoute(
            path: SalesStaffNavigation.reviewSegment,
            builder: (BuildContext context, GoRouterState state) {
              final String submissionId =
                  state.pathParameters['submissionId'] ?? '';
              // Two cubits, both bounded to this route. The product-selection
              // cubit is separate on purpose: it owns one catalogue read and a
              // local list, performs no write, and can be proven on its own
              // before the atomic confirmation is wired through it.
              return MultiBlocProvider(
                providers: <BlocProvider<dynamic>>[
                  BlocProvider<ReceiptReviewCubit>(
                    create: (BuildContext providerContext) =>
                        ReceiptReviewCubit(
                          repository: providerContext
                              .read<ReceiptExtractionRepository>(),
                          submissionId: submissionId,
                        ),
                  ),
                  BlocProvider<ReceiptProductSelectionCubit>(
                    create: (BuildContext providerContext) =>
                        ReceiptProductSelectionCubit(
                          providerContext.read<ReceiptRepository>(),
                        ),
                  ),
                ],
                child: SalesStaffReceiptReviewPage(submissionId: submissionId),
              );
            },
          ),
        ],
      ),
      // SS-07. Backed by list_my_staff_campaigns(), which takes ZERO arguments
      // and resolves through
      // resolve_retailer_member_organization('STAFF_CAMPAIGNS_VIEW') — a
      // SEPARATE permission from the Retailer Owner's, returning fewer columns
      // and only ACTIVE/SCHEDULED campaigns.
      //
      // READ-ONLY, and narrower than the Owner's: no Vendor name, no campaign
      // history, no Vendor action and no Owner action.
      GoRoute(
        path: SalesStaffNavigation.campaigns,
        builder: (BuildContext context, GoRouterState state) =>
            const SalesStaffCampaignsPage(),
        routes: <RouteBase>[
          // Nested, like the receipt review above and for the same reason.
          //
          // The id is an address only. get_my_staff_campaign() re-derives the
          // Retailer from auth.uid() AND re-applies the ACTIVE/SCHEDULED
          // filter, so a seller who types the id of a paused campaign reaches
          // the same not-found screen as one who types nonsense.
          GoRoute(
            path: SalesStaffNavigation.campaignDetailSegment,
            builder: (BuildContext context, GoRouterState state) =>
                SalesStaffCampaignDetailPage(
                  campaignId: state.pathParameters['campaignId'] ?? '',
                ),
          ),
        ],
      ),
    ],
  );
}
