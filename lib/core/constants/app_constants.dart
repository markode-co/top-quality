class AppConstants {
  const AppConstants._();

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: String.fromEnvironment('NEXT_PUBLIC_SUPABASE_URL'),
  );
  static const supabaseClientKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment(
      'NEXT_PUBLIC_SUPABASE_PUBLISHABLE_DEFAULT_KEY',
      defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
    ),
  );
  static const supabaseAnonKey = supabaseClientKey;
  static const supabaseFunctionsBaseUrl =
      String.fromEnvironment('SUPABASE_FUNCTIONS_URL');
  static const appTitle = 'FlowStock WMS';
  static const currencyCode = 'EGP';
}
