class AppConstants {
  const AppConstants._();

  /// Optional domain appended when a user signs in with a bare username
  /// (no "@"). Example: set `--dart-define=LOGIN_FALLBACK_DOMAIN=company.com`
  /// so "markode" signs in as "markode@company.com".
  static const loginFallbackDomain = String.fromEnvironment(
    'LOGIN_FALLBACK_DOMAIN',
    defaultValue: '',
  );

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: String.fromEnvironment('NEXT_PUBLIC_SUPABASE_URL'),
  );
  static const supabaseClientKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment(
      'NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY',
      defaultValue: String.fromEnvironment(
        'NEXT_PUBLIC_SUPABASE_ANON_KEY',
        defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
      ),
    ),
  );
  static const supabaseAnonKey = supabaseClientKey;
  static const supabaseFunctionsBaseUrl = String.fromEnvironment(
    'SUPABASE_FUNCTIONS_URL',
  );
  static const adminPortalEmails = String.fromEnvironment(
    'ADMIN_PORTAL_EMAILS',
    defaultValue: String.fromEnvironment(
      'HARD_ADMIN_EMAILS',
      defaultValue: 'ca.markode@gmail.com',
    ),
  );
  static const appTitle = 'Top Quality';
  static const currencyCode = 'EGP';

  static bool isAdminPortalEmail(String? email) {
    final normalized = (email ?? '').trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    for (final raw in adminPortalEmails.split(',')) {
      final candidate = raw.trim().toLowerCase();
      if (candidate.isNotEmpty && candidate == normalized) {
        return true;
      }
    }
    return false;
  }

  static String get primaryAdminPortalEmail {
    for (final raw in adminPortalEmails.split(',')) {
      final candidate = raw.trim().toLowerCase();
      if (candidate.isNotEmpty) {
        return candidate;
      }
    }
    return 'ca.markode@gmail.com';
  }
}
