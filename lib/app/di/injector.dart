import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/data/datasources/portal_context_data_source.dart';
import '../../features/auth/data/repositories/supabase_auth_repository.dart';
import '../../features/auth/data/repositories/supabase_portal_context_repository.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/audit/data/datasources/vendor_audit_log_rpc_data_source.dart';
import '../../features/audit/data/repositories/supabase_vendor_audit_log_repository.dart';
import '../../features/audit/domain/repositories/vendor_audit_log_repository.dart';
import '../../features/auth/domain/repositories/portal_context_repository.dart';
import '../../features/products/data/datasources/vendor_product_rpc_data_source.dart';
import '../../features/products/data/repositories/supabase_vendor_product_repository.dart';
import '../../features/products/domain/repositories/vendor_product_repository.dart';
import '../../features/receipts/data/datasources/receipt_rpc_data_source.dart';
import '../../features/receipts/data/datasources/submit_receipt_function_client.dart';
import '../../features/receipts/data/repositories/supabase_receipt_repository.dart';
import '../../features/receipts/data/services/image_picker_receipt_image_source.dart';
import '../../features/receipts/domain/repositories/receipt_repository.dart';
import '../../features/receipts/domain/services/receipt_image_source.dart';
import '../../features/retailers/data/datasources/vendor_retailer_rpc_data_source.dart';
import '../../features/retailers/data/repositories/supabase_vendor_retailer_repository.dart';
import '../../features/retailers/domain/repositories/vendor_retailer_repository.dart';
import '../../features/roles/data/datasources/vendor_role_rpc_data_source.dart';
import '../../features/roles/data/repositories/supabase_vendor_role_repository.dart';
import '../../features/roles/domain/repositories/vendor_role_repository.dart';
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

  // The Vendor Product reads. Three RPCs and no table access at all — both
  // product tables are default-deny with zero RLS policies and no privilege for
  // `authenticated`, so RPC is the only way in by design. The assignment
  // aggregation, the Retailer and relationship joins and the tenant scoping all
  // happen in SQL, and there is no storage client here because no product image
  // exists anywhere in the product.
  getIt.registerLazySingleton<VendorProductRepository>(
    () => SupabaseVendorProductRepository(
      rpc: VendorProductRpcDataSource.forClient(client),
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
  ReceiptRepository? receiptRepository,
  ReceiptImageSource? receiptImageSource,
  VendorRetailerRepository? vendorRetailerRepository,
  VendorUserRepository? vendorUserRepository,
  VendorRoleRepository? vendorRoleRepository,
  VendorProductRepository? vendorProductRepository,
  VendorAuditLogRepository? vendorAuditLogRepository,
}) {
  getIt.registerLazySingleton<AuthRepository>(() => authRepository);
  getIt.registerLazySingleton<PortalContextRepository>(
    () => portalContextRepository,
  );
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
}

/// Clears the graph. Used by tests so each one starts from a known state.
Future<void> resetDependencies() => getIt.reset();
