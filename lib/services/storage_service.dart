import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StorageService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Null get storageService => null;

  /// Upload file from device (Mobile only)
  Future<String?> uploadFile(File file, String path, {required Null Function(dynamic progress) onProgress}) async {
    final fileName = DateTime.now().millisecondsSinceEpoch.toString();
    final filePath = '$path/$fileName';

    final response = await _supabase.storage.from('posts').upload(filePath, file);

    if (response.isEmpty) {
      return _supabase.storage.from('posts').getPublicUrl(filePath);
    }
    return null;
  }

  /// Upload file from Web (XFile)
  Future<String?> uploadXFile(XFile xfile, String path) async {
    try {
      final fileName = DateTime.now().millisecondsSinceEpoch.toString();
      final filePath = '$path/$fileName';

      final bytes = await xfile.readAsBytes();

      final response = await _supabase.storage.from('posts').uploadBinary(
        filePath,
        bytes,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
      );

      if (response.isEmpty) {
        return _supabase.storage.from('posts').getPublicUrl(filePath);
      }
    } catch (e) {
      debugPrint('UploadXFile error: $e');
    }
    return null;
  }

 Future<String?> uploadBytes(
  Uint8List uint8list,
  String fileName, {
  required void Function(dynamic progress) onProgress,
}) async {
  try {
    final response = await Supabase.instance.client.storage
        .from('posts')
        .uploadBinary(
          fileName,
          uint8list,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
        );

    if (response.isEmpty) throw Exception('Upload failed');

    // Return public URL
    final publicUrl = Supabase.instance.client.storage
        .from('posts')
        .getPublicUrl(fileName);

    return publicUrl;
  } catch (e) {
    print('Upload failed: $e');
    return null;
  }
}

}
  // For web uploads
  // ignore: body_might_complete_normally_nullable
  Future<String?> uploadBytes(
    Uint8List bytes, 
    String fileName, 
    {Function(double)? onProgress}
  ) async {
    // Your Supabase upload implementation
  }

  // For mobile uploads  
  Future<String?> uploadFile(
    File file, 
    String fileName,
    {Function(double)? onProgress}
  ) async {
    return null;
  
    // Your Supabase upload implementation
  }