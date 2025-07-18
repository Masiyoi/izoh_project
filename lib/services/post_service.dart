import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/post_model.dart';

class PostService {
  final supabase = Supabase.instance.client;

  Future<void> createPost(PostModel post) async {
    final response = await supabase.from('posts').insert(post.toMap());
    if (response == null) {
      throw Exception('Failed to insert post');
    }
  }
  
  Future<List<PostModel>> getPosts() async {
    // TODO: Implement fetching posts from your backend or data source
    // Example:
    // return await fetchPostsFromApi();
return [];
}

  // ✅ This is the updated method you're missing
  Future<List<PostModel>> posts() async {
    final response = await supabase
        .from('posts')
        .select()
        .order('timestamp', ascending: false)
        .get();

    if (response.error != null) {
      throw Exception('Error fetching posts: ${response.error!.message}');
    }

    final List data = response.data as List;
    return data.map((item) => PostModel.fromMap(item)).toList();
  }
}

extension on PostgrestTransformBuilder<PostgrestList> {
  Future get() {
    throw UnimplementedError('get() has not been implemented yet.');
  }
}

