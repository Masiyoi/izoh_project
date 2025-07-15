import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> signInWithEmailAndPassword(String email, String password) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (response.user == null) {
        throw Exception('Supabase sign-in failed: No user returned');
      }
      print('Supabase UID: ${response.user!.id}');
    } catch (e) {
      throw Exception('Error signing in: $e');
    }
  }

  Future<void> signUp(String email, String password, String username) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
      );
      final user = response.user;
      if (user == null) {
        throw Exception('Supabase sign-up failed: No user returned');
      }
      await _supabase.from('profiles').insert({
        'id': user.id,
        'username': username,
        'created_at': DateTime.now().toIso8601String(),
      });
      print('Supabase UID: ${user.id}');
    } catch (e) {
      throw Exception('Error signing up: $e');
    }
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}