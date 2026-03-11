import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:top_quality/core/constants/app_constants.dart';

/// Bootstrap Supabase specifically for Storage usage.
class SupabaseStorageBootstrap {
  SupabaseStorageBootstrap._();

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    if (AppConstants.supabaseUrl.isEmpty ||
        AppConstants.supabaseClientKey.isEmpty) {
      return;
    }
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseClientKey,
    );
    _initialized = true;
  }

  static SupabaseClient get client {
    if (!_initialized) {
      throw Exception('SupabaseStorageBootstrap.initialize() not called');
    }
    return Supabase.instance.client;
  }
}
