import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/data/datasources/lifecycle_access_rpc_data_source.dart';
import '../../features/auth/data/datasources/portal_context_data_source.dart';
import '../../features/auth/data/repositories/supabase_auth_repository.dart';
import '../../features/auth/data/repositories/supabase_lifecycle_access_repository.dart';
import '../../features/auth/data/repositories/supabase_portal_context_repository.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/domain/repositories/lifecycle_access_repository.dart';
import '../../features/audit/data/datasources/vendor_audit_log_rpc_data_source.dart';
import '../../features/audit/data/repositories/supabase_vendor_audit_log_repository.dart';
import '../../features/audit/domain/repositories/vendor_audit_log_repository.dart';
import '../../features/auth/domain/repositories/portal_context_repository.dart';
import '../../features/dashboard/data/datasources/retailer_owner_overview_rpc_data_source.dart';
import '../../features/dashboard/data/datasources/vendor_dashboard_rpc_data_source.dart';
import '../../features/dashboard/data/repositories/supabase_retailer_owner_overview_repository.dart';
import '../../features/dashboard/data/repositories/supabase_vendor_dashboard_repository.dart';
import '../../features/dashboard/domain/repositories/retailer_owner_overview_repository.dart';
import '../../features/dashboard/domain/repositories/vendor_dashboard_repository.dart';
import '../../features/products/data/datasources/retailer_product_rpc_data_source.dart';
import '../../features/products/data/datasources/vendor_product_assignment_rpc_data_source.dart';
import '../../features/products/data/datasources/vendor_product_rpc_data_source.dart';
import '../../features/products/data/datasources/vendor_product_write_rpc_data_source.dart';
import '../../features/products/data/repositories/supabase_retailer_product_repository.dart';
import '../../features/products/data/repositories/supabase_vendor_product_repository.dart';
import '../../features/products/domain/repositories/retailer_product_repository.dart';
import '../../features/products/domain/repositories/vendor_product_repository.dart';
import '../../features/profile/data/datasources/vendor_profile_rpc_data_source.dart';
import '../../features/profile/data/repositories/supabase_vendor_profile_repository.dart';
import '../../features/profile/domain/repositories/vendor_profile_repository.dart';
import '../../features/receipts/data/datasources/receipt_rpc_data_source.dart';
import '../../features/receipts/data/datasources/submit_receipt_function_client.dart';
import '../../features/receipts/data/repositories/supabase_receipt_repository.dart';
import '../../features/receipts/data/services/image_picker_receipt_image_source.dart';
import '../../features/receipts/domain/repositories/receipt_repository.dart';
import '../../features/receipts/domain/services/receipt_image_source.dart';
import '../../features/retailers/data/datasources/vendor_retailer_capability_rpc_data_source.dart';
import '../../features/retailers/data/datasources/vendor_retailer_lifecycle_rpc_data_source.dart';
import '../../features/retailers/data/datasources/vendor_retailer_rpc_data_source.dart';
import '../../features/retailers/data/repositories/supabase_vendor_retailer_lifecycle_repository.dart';
import '../../features/retailers/data/repositories/supabase_vendor_retailer_repository.dart';
import '../../features/retailers/domain/repositories/vendor_retailer_lifecycle_repository.dart';
import '../../features/retailers/domain/repositories/vendor_retailer_repository.dart';
import '../../features/roles/data/datasources/vendor_role_rpc_data_source.dart';
import '../../features/roles/data/repositories/supabase_vendor_role_repository.dart';
import '../../features/roles/domain/repositories/vendor_role_repository.dart';
import '../../features/shops/data/datasources/retailer_shop_rpc_data_source.dart';
import '../../features/shops/data/repositories/supabase_retailer_shop_repository.dart';
import '../../features/shops/domain/repositories/retailer_shop_repository.dart';
import '../../features/staff/data/datasources/retailer_staff_invitation_rpc_data_source.dart';
import '../../features/staff/data/datasources/retailer_staff_lifecycle_rpc_data_source.dart';
import '../../features/staff/data/datasources/retailer_staff_rpc_data_source.dart';
import '../../features/staff/data/datasources/retailer_staff_shop_assignment_rpc_data_source.dart';
import '../../features/staff/data/repositories/supabase_retailer_staff_invitation_repository.dart';
import '../../features/staff/data/repositories/supabase_retailer_staff_lifecycle_repository.dart';
import '../../features/staff/data/repositories/supabase_retailer_staff_repository.dart';
import '../../features/staff/data/repositories/supabase_retailer_staff_shop_assignment_repository.dart';
import '../../features/staff/domain/repositories/retailer_staff_invitation_repository.dart';
import '../../features/staff/domain/repositories/retailer_staff_lifecycle_repository.dart';
import '../../features/staff/domain/repositories/retailer_staff_repository.dart';
import '../../features/staff/domain/repositories/retailer_staff_shop_assignment_repository.dart';
import '../../features/users/data/datasources/vendor_user_rpc_data_source.dart';
import '../../features/users/data/repositories/supabase_vendor_user_repository.dart';
import '../../features/users/domain/repositories/vendor_user_repository.dart';
import '../config/app_config.dart';

/// The service locator.
///
/// Only *shared foundation* dependencies live here — the things every role needs
/// one of. Role-specific shell BLoCs are deliberately absent: each shell
/// constructs its own through a `BlocProvider`.
///
/// The presentation layer resolves the **interfaces** from here and never the
/// Supabase-backed classes by name, and never `Supabase.instance.client`. This
/// file is the one seam where the concrete implementations are chosen, which is
/// what keeps "how we authenticate" and "how we upload" swappable details.
final GetIt getIt = GetIt.instance;

/// Registers the shared dependency graph against the live Supabase client.
///
/// Safe to call more than once.
Future<void> configureDependencies() async {
  if (getIt.isRegistered<AuthRepository>()) {
    return;
  }

  final SupabaseClient client = Supabase.instance.client;

  getIt.registerLazySingleton<AuthRepository>(
    () => SupabaseAuthRepository(client.auth),
  );

  getIt.registerLazySingleton<PortalContextRepository>(
    () => SupabasePortalContextRepository(
      PortalContextDataSource(supabasePortalContextInvoker(client)),
    ),
  );

  // The self-only lifecycle diagnostic, read ONLY by the access-denied screen
  // after a refusal has already been decided. It is a sibling of the portal
  // context, never a replacement: that one decides routing, this one explains a
  // denial, and nothing may branch on this one to admit a request.
  //
  // Registered lazily like everything here, so a session that never reaches a
  // denial never constructs it.
  getIt.registerLazySingleton<LifecycleAccessRepository>(
    () => SupabaseLifecycleAccessRepository(
      LifecycleAccessRpcDataSource(supabaseLifecycleAccessInvoker(client)),
    ),
  );

  // One HTTP client for the app's lifetime, so a submission does not pay for a
  // fresh connection pool each time. It is never given a key of its own: the
  // token and the publishable key are attached per request by the function
  // client below.
  getIt.registerLazySingleton<http.Client>(http.Client.new);

  getIt.registerLazySingleton<ReceiptImageSource>(
    ImagePickerReceiptImageSource.new,
  );

  getIt.registerLazySingleton<ReceiptRepository>(
    () => SupabaseReceiptRepository(
      rpc: ReceiptRpcDataSource.forClient(client),
      functions: SubmitReceiptFunctionClient(
        endpoint: SubmitReceiptFunctionClient.endpointFor(
          AppConfig.supabaseUrl,
        ),
        // Public by definition — the same value the web bundle embeds, supplied
        // through a dart-define. The privileged key exists only inside the Edge
        // Function's own environment and appears nowhere in this application.
        publishableKey: AppConfig.supabasePublishableKey,
        accessToken: supabaseAccessTokenProvider(client),
        httpClient: getIt<http.Client>(),
      ),
    ),
  );

  // The Vendor Retailer reads. Three RPCs and no table access at all — the
  // join, the shop counting and the tenant scoping happen in SQL, so there is
  // nothing to configure here beyond the client the calls travel on.
  getIt.registerLazySingleton<VendorRetailerRepository>(
    () => SupabaseVendorRetailerRepository(
      rpc: VendorRetailerRpcDataSource.forClient(client),
    ),
  );

  // The Vendor Retailer **lifecycle**: one write, and one capability probe.
  //
  // Registered separately from the reads above, and behind a separate interface,
  // because that one's contract guarantees it is read-only and its boundary test
  // asserts exactly that. Two data sources behind one repository, so each one's
  // payload vocabulary can be asserted exactly: the write takes a relationship id
  // and one of two status tokens, the probe takes an organization id and a
  // permission code, and neither can express the other's arguments.
  //
  // **No table access at all.** `organizations` and `vendor_retailers` are
  // SELECT-only for the browser with read-only policies and no INSERT/UPDATE/
  // DELETE privilege of any kind, so there is no route to a status change but
  // this RPC — which moves both status columns atomically, each with a
  // compare-and-set predicate and a checked row count, and writes its own audit
  // row inside the same transaction.
  //
  // **This is the same deployed function the Next.js portal calls.** There is no
  // mobile twin and no second definition of "deactivate a Retailer", so the two
  // clients cannot disagree about the multi-Vendor refusal, about which pairs are
  // eligible, or about what survives a deactivation.
  //
  // **No service-role key is registered here or exists anywhere in this
  // application.** Both calls travel on the caller's own session, which is the
  // only reason `auth.uid()` means anything inside either function — a
  // service-role connection has no identity for them to derive and could only
  // ever be refused.
  getIt.registerLazySingleton<VendorRetailerLifecycleRepository>(
    () => SupabaseVendorRetailerLifecycleRepository(
      rpc: VendorRetailerLifecycleRpcDataSource.forClient(client),
      capability: VendorRetailerCapabilityRpcDataSource.forClient(client),
    ),
  );

  // The Vendor User reads. Two RPCs and no table access at all — the four-table
  // join, the ACTIVE-role filter, the name composition and the tenant scoping
  // all happen in SQL, so there is nothing to configure here beyond the client
  // the calls travel on.
  getIt.registerLazySingleton<VendorUserRepository>(
    () => SupabaseVendorUserRepository(
      rpc: VendorUserRpcDataSource.forClient(client),
    ),
  );

  // The Vendor Role reads. Three RPCs and no table access at all — the
  // role→permission join, the permission count and the Vendor-scoped assigned
  // member count all happen in SQL, so there is nothing to configure here
  // beyond the client the calls travel on.
  getIt.registerLazySingleton<VendorRoleRepository>(
    () => SupabaseVendorRoleRepository(
      rpc: VendorRoleRpcDataSource.forClient(client),
    ),
  );

  // The Vendor Product reads and writes. Six RPCs and no table access at all —
  // both product tables are default-deny with zero RLS policies and no privilege
  // for `authenticated`, so RPC is the only way in by design. The assignment
  // aggregation, the Retailer and relationship joins, the tenant scoping, every
  // normalization rule, both uniqueness authorities and the audit row for each
  // write all happen in SQL, and there is no storage client here because no
  // product image exists anywhere in the product.
  //
  // Three data sources behind one repository: the reads take no argument or one
  // product id, the product writes take product fields, and the assignment
  // writes take two addresses under a *different* permission
  // (`PRODUCT_RETAILER_ASSIGN`, which the backend proved is distinct from
  // `PRODUCTS_MANAGE` in both directions). Keeping the three payload
  // vocabularies in separate files is what makes each one's boundary test able to
  // assert its parameter set exactly. All three travel on the caller's own token
  // — there is no service-role client here, and a service-role connection has no
  // `auth.uid()` for the functions to derive an identity from.
  getIt.registerLazySingleton<VendorProductRepository>(
    () => SupabaseVendorProductRepository(
      rpc: VendorProductRpcDataSource.forClient(client),
      writes: VendorProductWriteRpcDataSource.forClient(client),
      assignments: VendorProductAssignmentRpcDataSource.forClient(client),
    ),
  );

  // The Vendor Audit Log read. One RPC and no table access at all — the tenant
  // predicate, the keyset page boundary, the membership-scoped actor join and
  // the closed metadata name whitelist all happen in SQL. `authenticated` does
  // hold SELECT on `audit_logs`, so a direct read would *work*; it is not done
  // because it would put `metadata`, `entity_id`, `ip_address`, `user_agent` and
  // the auth user id on a phone and move a privacy decision into Dart.
  getIt.registerLazySingleton<VendorAuditLogRepository>(
    () => SupabaseVendorAuditLogRepository(
      rpc: VendorAuditLogRpcDataSource.forClient(client),
    ),
  );

  // The Vendor Dashboard summary read. One RPC, zero arguments, and no table
  // access at all — the Vendor resolution, the three permission checks and all
  // four count definitions happen in SQL. The web assembles the same page from
  // four direct table reads plus an authorization round trip; reproducing that
  // here would put the metric definitions into a second client free to drift
  // from the first, including the fact that two of the four counts are
  // deployment-wide catalogue figures rather than this Vendor's.
  getIt.registerLazySingleton<VendorDashboardRepository>(
    () => SupabaseVendorDashboardRepository(
      rpc: VendorDashboardRpcDataSource.forClient(client),
    ),
  );

  // The three Retailer read-portal contracts. Four RPCs, all zero-argument, and
  // no table access at all — every tenant scope, permission gate, role-dependent
  // status filter, shop-assignment join and invitation state derivation happens
  // in SQL.
  //
  // A direct table read is not merely avoided here, it would not work.
  // `retailer_shops` carries one vendor-scoped SELECT policy that returns zero
  // rows to a Retailer Owner, and both product tables are default-deny with no
  // privilege for `authenticated` — so a client that reproduced these queries
  // would render an empty estate and an empty catalogue for every Retailer and
  // look entirely plausible doing it.
  //
  // No write RPC is registered for any of them, because none exists in the
  // Retailer portal: shop create/edit/status, invitation send/resend/revoke,
  // membership role and status changes, and product assignment are all either
  // Vendor operations on other permissions or Edge Functions this application
  // never calls.
  getIt.registerLazySingleton<RetailerShopRepository>(
    () => SupabaseRetailerShopRepository(
      rpc: RetailerShopRpcDataSource.forClient(client),
    ),
  );

  getIt.registerLazySingleton<RetailerStaffRepository>(
    () => SupabaseRetailerStaffRepository(
      rpc: RetailerStaffRpcDataSource.forClient(client),
    ),
  );

  getIt.registerLazySingleton<RetailerProductRepository>(
    () => SupabaseRetailerProductRepository(
      rpc: RetailerProductRpcDataSource.forClient(client),
    ),
  );

  // The Retailer staff **invitation** contracts: one zero-argument read for the
  // shop picker, and one Edge Function call to send.
  //
  // The read is `list_retailer_staff_assignable_shops()`, which is the only
  // Retailer contract that returns a shop id — deliberately, and for exactly one
  // purpose: so the id can be handed straight back to the reservation. A direct
  // table read would not work in its place, because the shop table carries one
  // vendor-scoped SELECT policy that returns zero rows to a Retailer Owner.
  //
  // The send goes to the shared `send-retailer-staff-invitation` function, the
  // same one the web portal posts to, so reserve → prepare → send → record
  // exists once for both clients. **No service-role key and no Resend
  // credential is registered here or exists anywhere in this application**:
  // three of the four RPCs behind that function are granted to the privileged
  // database role alone and the delivery credential lives only in the function's own
  // environment, which is precisely why sending is a function call rather than
  // an RPC. It travels on the caller's own session, so `auth.uid()` is the real
  // person and the Retailer is resolved in PostgreSQL.
  //
  // No invitation acceptance, revoke, resend, role change, membership status
  // change or post-acceptance shop reassignment is registered, because none is
  // implemented: acceptance happens in the emailed link, and the rest are
  // separate backend operations.
  getIt.registerLazySingleton<RetailerStaffInvitationRepository>(
    () => SupabaseRetailerStaffInvitationRepository(
      rpc: RetailerStaffInvitationRpcDataSource.forClient(client),
    ),
  );

  // The Retailer staff **post-acceptance shop-assignment** write: one RPC,
  // `set_retailer_staff_shop_assignments(uuid, uuid[])`, and no table access at
  // all.
  //
  // A direct write is not merely avoided here, it would not work.
  // `retailer_shop_members` grants nothing to `authenticated`, and the
  // same-Retailer trigger, the ACTIVE-shop validation, the `removed_at`
  // retirement and the audit row all live in SQL — inside one transaction the
  // client could not reproduce even if the privileges existed.
  //
  // This is the **same deployed function the Next.js portal calls**. There is no
  // mobile twin and no second definition of "replace a staff member's shops", so
  // the two clients cannot disagree about the zero-shop refusal, about which
  // memberships are eligible, or about what happens to an assignment whose shop
  // is no longer active.
  //
  // It travels on the caller's own session — the only reason `auth.uid()` means
  // anything inside the function. **No service-role key is registered here or
  // exists anywhere in this application**, and a service-role connection would
  // have no identity for the function to resolve.
  //
  // The assignable-shop picker needs no registration of its own: it reads
  // `list_retailer_staff_assignable_shops()` through
  // `RetailerAssignableShopsReader`, which the invitation repository above
  // already implements. One deployed contract, one instance, one Dart path.
  //
  // No staff activation, deactivation, role change, invitation accept, revoke or
  // resend is registered, because none is implemented.
  getIt.registerLazySingleton<RetailerStaffShopAssignmentRepository>(
    () => SupabaseRetailerStaffShopAssignmentRepository(
      rpc: RetailerStaffShopAssignmentRpcDataSource.forClient(client),
    ),
  );

  // The Retailer staff **lifecycle** write: one RPC,
  // `set_retailer_staff_membership_status(uuid, text)`, and no table access at
  // all.
  //
  // Registered separately from both staff interfaces above, and behind its own,
  // because each of those documents what it is: the roster repository guarantees
  // it holds no write, and the shop-assignment repository is about *which shops*
  // an accepted member works in, on a different permission
  // (`RETAILER_STAFF_SHOP_ASSIGN`). This operation is about *whether they may
  // work at all*, on `RETAILER_STAFF_MANAGE`.
  //
  // A direct write is not merely avoided here, it would not work.
  // `organization_members` is SELECT-only for the browser with a single read
  // policy and no INSERT/UPDATE/DELETE privilege of any kind. The status column,
  // `deactivated_at` and the audit row all move inside one transaction, under a
  // `FOR UPDATE` lock, after the function has read the target's COMPLETE ACTIVE
  // role set and refused every Owner, multi-role, role-less, invited, suspended,
  // cross-tenant and self target — none of which this client could reproduce.
  //
  // This is the **same deployed function the Next.js portal calls**. There is no
  // mobile twin and no second definition of "deactivate a staff member", so the
  // two clients cannot disagree about the Owner exclusion or about what survives
  // a deactivation.
  //
  // It travels on the caller's own session. **No service-role key is registered
  // here or exists anywhere in this application** — and the migration revokes
  // that role explicitly, because a privileged connection has no `auth.uid()`
  // for the function to attribute its audit row to.
  getIt.registerLazySingleton<RetailerStaffLifecycleRepository>(
    () => SupabaseRetailerStaffLifecycleRepository(
      rpc: RetailerStaffLifecycleRpcDataSource.forClient(client),
    ),
  );

  // The Retailer Owner Overview read. One RPC, zero arguments, and no table
  // access at all — the organization resolution, the role and permission gates,
  // the single-qualifying-organization rule and both shop counts happen in SQL.
  //
  // A direct table read is not merely avoided here, it would not work:
  // `retailer_shops` carries exactly one vendor-scoped SELECT policy, which
  // returns zero rows to a Retailer Owner by design. A client counting shops
  // itself would render `0` for every Owner and look entirely plausible doing
  // it, which is precisely why the counts are computed by the function against
  // the resolved organization id rather than a caller-supplied one.
  getIt.registerLazySingleton<RetailerOwnerOverviewRepository>(
    () => SupabaseRetailerOwnerOverviewRepository(
      rpc: RetailerOwnerOverviewRpcDataSource.forClient(client),
    ),
  );

  // The Vendor company/profile self-read. One RPC, zero arguments, and no table
  // access at all — the self predicate (`user_id = auth.uid()`), the tenant
  // predicate, the display-name composition, the ACTIVE-role filter and the role
  // ordering all happen in SQL. `authenticated` does hold SELECT on `profiles`,
  // `organization_members`, `member_roles` and `roles`, so a direct read would
  // partly *work*; it is not done because reassembling "who am I" in Dart would
  // put a second definition of the composed name into a client free to drift from
  // the database and from the web — and because the caller's own row is not
  // identifiable in the directory read without matching a locally composed name.
  //
  // The company half needs nothing here: the organization name comes from the
  // PortalContext this graph already resolves.
  getIt.registerLazySingleton<VendorProfileRepository>(
    () => SupabaseVendorProfileRepository(
      rpc: VendorProfileRpcDataSource.forClient(client),
    ),
  );
}

/// Supplies the current access token for the receipt upload.
///
/// ## Token expiry is handled once, here
///
/// `supabase_flutter` refreshes in the background, but an app resumed from
/// suspension can still hold a session that expired while it was away. Sending
/// that token would produce a `401` only *after* a full 10 MiB upload, so an
/// expired session is refreshed **before** any bytes are sent. If the refresh
/// fails there is no usable session, and returning null ends the submission as
/// `unauthenticated` without a request ever leaving the device.
///
/// This is not a retry of the upload. It runs before the upload, exactly once,
/// and never re-sends a request that has already been made.
ReceiptAccessTokenProvider supabaseAccessTokenProvider(SupabaseClient client) {
  return () async {
    Session? session = client.auth.currentSession;
    if (session == null) {
      return null;
    }

    if (session.isExpired) {
      try {
        session = (await client.auth.refreshSession()).session;
      } on Object {
        return null;
      }
    }

    return session?.accessToken;
  };
}

/// Registers a supplied dependency graph, for tests and previews that stand up
/// no Supabase client.
///
/// The two authentication dependencies are required so a test can never
/// accidentally fall through to the live client. The receipt and Retailer
/// dependencies are optional because most tests never enter the shell that
/// needs them.
void registerTestDependencies({
  required AuthRepository authRepository,
  required PortalContextRepository portalContextRepository,
  LifecycleAccessRepository? lifecycleAccessRepository,
  ReceiptRepository? receiptRepository,
  ReceiptImageSource? receiptImageSource,
  VendorRetailerRepository? vendorRetailerRepository,
  VendorRetailerLifecycleRepository? vendorRetailerLifecycleRepository,
  VendorUserRepository? vendorUserRepository,
  VendorRoleRepository? vendorRoleRepository,
  VendorProductRepository? vendorProductRepository,
  VendorAuditLogRepository? vendorAuditLogRepository,
  VendorDashboardRepository? vendorDashboardRepository,
  VendorProfileRepository? vendorProfileRepository,
  RetailerOwnerOverviewRepository? retailerOwnerOverviewRepository,
  RetailerShopRepository? retailerShopRepository,
  RetailerStaffRepository? retailerStaffRepository,
  RetailerStaffInvitationRepository? retailerStaffInvitationRepository,
  RetailerStaffShopAssignmentRepository? retailerStaffShopAssignmentRepository,
  RetailerStaffLifecycleRepository? retailerStaffLifecycleRepository,
  RetailerProductRepository? retailerProductRepository,
}) {
  getIt.registerLazySingleton<AuthRepository>(() => authRepository);
  getIt.registerLazySingleton<PortalContextRepository>(
    () => portalContextRepository,
  );
  // Optional, like every non-authentication dependency here: only a test that
  // actually reaches the access-denied screen needs one.
  if (lifecycleAccessRepository != null) {
    getIt.registerLazySingleton<LifecycleAccessRepository>(
      () => lifecycleAccessRepository,
    );
  }
  if (receiptRepository != null) {
    getIt.registerLazySingleton<ReceiptRepository>(() => receiptRepository);
  }
  if (receiptImageSource != null) {
    getIt.registerLazySingleton<ReceiptImageSource>(() => receiptImageSource);
  }
  if (vendorRetailerRepository != null) {
    getIt.registerLazySingleton<VendorRetailerRepository>(
      () => vendorRetailerRepository,
    );
  }
  if (vendorRetailerLifecycleRepository != null) {
    getIt.registerLazySingleton<VendorRetailerLifecycleRepository>(
      () => vendorRetailerLifecycleRepository,
    );
  }
  if (vendorUserRepository != null) {
    getIt.registerLazySingleton<VendorUserRepository>(
      () => vendorUserRepository,
    );
  }
  if (vendorRoleRepository != null) {
    getIt.registerLazySingleton<VendorRoleRepository>(
      () => vendorRoleRepository,
    );
  }
  if (vendorProductRepository != null) {
    getIt.registerLazySingleton<VendorProductRepository>(
      () => vendorProductRepository,
    );
  }
  if (vendorAuditLogRepository != null) {
    getIt.registerLazySingleton<VendorAuditLogRepository>(
      () => vendorAuditLogRepository,
    );
  }
  if (vendorDashboardRepository != null) {
    getIt.registerLazySingleton<VendorDashboardRepository>(
      () => vendorDashboardRepository,
    );
  }
  if (vendorProfileRepository != null) {
    getIt.registerLazySingleton<VendorProfileRepository>(
      () => vendorProfileRepository,
    );
  }
  if (retailerOwnerOverviewRepository != null) {
    getIt.registerLazySingleton<RetailerOwnerOverviewRepository>(
      () => retailerOwnerOverviewRepository,
    );
  }
  if (retailerShopRepository != null) {
    getIt.registerLazySingleton<RetailerShopRepository>(
      () => retailerShopRepository,
    );
  }
  if (retailerStaffRepository != null) {
    getIt.registerLazySingleton<RetailerStaffRepository>(
      () => retailerStaffRepository,
    );
  }
  if (retailerStaffInvitationRepository != null) {
    getIt.registerLazySingleton<RetailerStaffInvitationRepository>(
      () => retailerStaffInvitationRepository,
    );
  }
  if (retailerStaffShopAssignmentRepository != null) {
    getIt.registerLazySingleton<RetailerStaffShopAssignmentRepository>(
      () => retailerStaffShopAssignmentRepository,
    );
  }
  if (retailerStaffLifecycleRepository != null) {
    getIt.registerLazySingleton<RetailerStaffLifecycleRepository>(
      () => retailerStaffLifecycleRepository,
    );
  }
  if (retailerProductRepository != null) {
    getIt.registerLazySingleton<RetailerProductRepository>(
      () => retailerProductRepository,
    );
  }
}

/// Clears the graph. Used by tests so each one starts from a known state.
Future<void> resetDependencies() => getIt.reset();
