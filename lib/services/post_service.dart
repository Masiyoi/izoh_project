import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/post_model.dart';

class PostService {
  final supabase = Supabase.instance.client;

  Future<void> createPost(PostModel post) async {
    final response = await supabase.from('posts').insert({
      'id': post.id,
      'caption': post.caption,
      'media_url': post.mediaUrl,
      'media_type': post.mediaType,
      'timestamp': post.timestamp.toIso8601String(),
      'user_id': post.uid,
    });

    if (response == null) {
      throw Exception('Failed to insert post');
    }
  }

  // ✅ This is the updated method you're missing
  Future<List<PostModel>> Posts() async {
    final response = await supabase
        .from('posts')
        .select()
        .order('timestamp', ascending: false);

    if (response is PostgrestException) {
      throw Exception('Error fetching posts: ${response.message}');
    }

    final List data = response;
    return data.map((item) => PostModel.fromMap(item)).toList();
  }
}

extension on PostgrestList {
  Null get message => null;
}
