import 'dart:io';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

Future<String?> uploadFileToSupabase(File file, String folder) async {
  final supabase = Supabase.instance.client;
  final fileExt = path.extension(file.path);
  final fileName = '${DateTime.now().millisecondsSinceEpoch}$fileExt';
  final filePath = '$folder/$fileName';

  final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';

  final bytes = await file.readAsBytes();
  try {
    await supabase.storage
        .from('media')
        .uploadBinary(filePath, bytes, fileOptions: FileOptions(contentType: mimeType));
  } catch (e) {
    debugPrint('Upload error: $e');
    return null;
  }

  final publicUrl = supabase.storage.from('media').getPublicUrl(filePath);
  return publicUrl;
}

// Removed unnecessary String extension that caused error handling to always be unreachable.
