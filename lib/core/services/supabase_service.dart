import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/app_constants.dart';

final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  return SupabaseService();
});

class SupabaseService {
  bool get isConfigured => AppConstants.isSupabaseConfigured;

  SupabaseClient get client {
    if (!isConfigured) {
      throw StateError(
        'Supabase is not configured. Pass SUPABASE_URL and '
        'SUPABASE_ANON_KEY with --dart-define.',
      );
    }

    return Supabase.instance.client;
  }

  GoTrueClient get auth => client.auth;
}
