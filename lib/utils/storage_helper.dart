import 'dart:io';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:supabase_flutter/supabase_flutter.dart';

Future<String?> uploadFileToSupabase(File file, String folder) async {
  final supabase = Supabase.instance.client;
  final fileExt = path.extension(file.path);
  final fileName = '${DateTime.now().millisecondsSinceEpoch}$fileExt';
  final filePath = '$folder/$fileName';

  final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';

  final bytes = await file.readAsBytes();
  final response = await supabase.storage
      .from('media')
      .uploadBinary(filePath, bytes, fileOptions: FileOptions(contentType: mimeType));

  if (response.error != null) {
    print('Upload error: ${response.error!.message}');
    return null;
  }

  final publicUrl = supabase.storage.from('media').getPublicUrl(filePath);
  return publicUrl;
}

extension on String {
  Null get error => null;
}
