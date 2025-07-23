// lib/utils/supabase_client.dart
import 'package:supabase_flutter/supabase_flutter.dart';

export 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseClientUtil {
  static final SupabaseClient client = Supabase.instance.client;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: 'https://oegfcsyndbycisohwbvg.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9lZ2Zjc3luZGJ5Y2lzb2h3YnZnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA5NTA4NTksImV4cCI6MjA2NjUyNjg1OX0.5pGM2Pfne23eqXuoWVRLMVH1PHeU4a4FzGHHZhPpTe8',
      debug: true, // Optional: Enable for debugging
    );
  }
}