import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/app_config.dart';
import 'di/injector.dart';

/// Starts the application.
///
/// Supabase is initialized with the URL and the **publishable** key only — the
/// same two values the web bundle embeds, and the only two that may ever appear
/// in a mobile binary. Anything in the binary is public; an APK is trivially
/// unpacked. The service-role key, the Resend key and any future OCR credential
/// stay server-side, exactly as they do in the web repository.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  AppConfig.validate();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  await configureDependencies();

  if (kDebugMode) {
    debugPrint('Supabase client initialized successfully.');
  }

  runApp(const SaleRewardApp());
}
