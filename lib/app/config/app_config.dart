abstract final class AppConfig {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static void validate() {
    if (supabaseUrl.isEmpty) {
      throw StateError(
        'SUPABASE_URL is missing. Run Flutter with '
        '--dart-define-from-file=dart_defines.json.',
      );
    }

    if (supabasePublishableKey.isEmpty) {
      throw StateError(
        'SUPABASE_PUBLISHABLE_KEY is missing. Run Flutter with '
        '--dart-define-from-file=dart_defines.json.',
      );
    }

    final Uri? uri = Uri.tryParse(supabaseUrl);

    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw StateError('SUPABASE_URL is not a valid HTTPS URL.');
    }
  }
}
