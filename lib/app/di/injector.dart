import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/data/datasources/portal_context_data_source.dart';
import '../../features/auth/data/repositories/supabase_auth_repository.dart';
import '../../features/auth/data/repositories/supabase_portal_context_repository.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/domain/repositories/portal_context_repository.dart';
import '../../features/receipts/data/datasources/receipt_rpc_data_source.dart';
import '../../features/receipts/data/datasources/submit_receipt_function_client.dart';
import '../../features/receipts/data/repositories/supabase_receipt_repository.dart';
import '../../features/receipts/data/services/image_picker_receipt_image_source.dart';
import '../../features/receipts/domain/repositories/receipt_repository.dart';
import '../../features/receipts/domain/services/receipt_image_source.dart';
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
/// accidentally fall through to the live client. The receipt dependencies are
/// optional because most tests never enter the Sales Staff shell.
void registerTestDependencies({
  required AuthRepository authRepository,
  required PortalContextRepository portalContextRepository,
  ReceiptRepository? receiptRepository,
  ReceiptImageSource? receiptImageSource,
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
}

/// Clears the graph. Used by tests so each one starts from a known state.
Future<void> resetDependencies() => getIt.reset();
