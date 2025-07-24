import 'package:flutter/material.dart';
import 'package:unic_connect/utils/supabase_client.dart';
import 'package:uuid/uuid.dart';

class CommentsScreen extends StatefulWidget {
  final String postId;

  const CommentsScreen({super.key, required this.postId});

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final supabase = SupabaseClientUtil.client;
  final TextEditingController _commentController = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  Map<String, dynamic>? _post;
  bool _isLoading = true;
  bool _isPostLoading = true;
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _loadPost();
    _loadComments();
    _setupRealtime();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadPost() async {
    setState(() => _isPostLoading = true);
    try {
      print('Loading post with ID: ${widget.postId}');
      
      // First, get the post with profile - using correct field names from your database
      final postResponse = await supabase
          .from('posts')
          .select('''
            *,
            profiles(username, profile_image_url, avatar_url)
          ''')
          .eq('id', widget.postId)
          .single();
      
      print('Post response: $postResponse');

      // Then get likes count separately
      final likesResponse = await supabase
          .from('post_likes')
          .select('id')
          .eq('post_id', widget.postId);

      // Get comments count separately
      final commentsResponse = await supabase
          .from('comments')
          .select('id')
          .eq('post_id', widget.postId);
      
      // Try profile_image_url first, then avatar_url as fallback
      String? avatarUrl = postResponse['profiles']?['profile_image_url'] ?? 
                         postResponse['profiles']?['avatar_url'];
      
      final postData = {
        ...postResponse,
        'username': postResponse['profiles']?['username'] ?? 'Unknown',
        'avatar_url': avatarUrl,
        'likes_count': likesResponse.length,
        'comments_count': commentsResponse.length,
      };
      
      print('Final post data: $postData');
      print('Avatar URL: $avatarUrl');
      
      setState(() {
        _post = postData;
        _isPostLoading = false;
      });
    } catch (e) {
      print('Error loading post: $e');
      print('Post ID: ${widget.postId}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading post: $e'), backgroundColor: Colors.red),
      );
      setState(() => _isPostLoading = false);
    }
  }

  Future<void> _loadComments() async {
    setState(() => _isLoading = true);
    try {
      final response = await supabase
          .from('comments')
          .select('''
            *,
            profiles(username, profile_image_url, avatar_url)
          ''')
          .eq('post_id', widget.postId)
          .order('created_at', ascending: true);
      
      setState(() {
        _comments = response.map<Map<String, dynamic>>((comment) => {
              ...comment,
              'username': comment['profiles']?['username'] ?? 'Unknown',
              'avatar_url': comment['profiles']?['profile_image_url'] ?? 
                           comment['profiles']?['avatar_url'],
            }).toList();
        _isLoading = false;
      });
      
      // Update post comments count after loading comments
      if (_post != null) {
        setState(() {
          _post!['comments_count'] = _comments.length;
        });
      }
    } catch (e) {
      print('Error loading comments: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading comments: $e'), backgroundColor: Colors.red),
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _setupRealtime() async {
    _realtimeChannel = supabase.channel('comments-${widget.postId}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'comments',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'post_id',
          value: widget.postId,
        ),
        callback: (payload) {
          _loadComments();
        },
      )
      ..subscribe();
  }

  Future<void> _addComment() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to comment'), backgroundColor: Colors.red),
      );
      return;
    }

    final content = _commentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comment cannot be empty'), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      await supabase.from('comments').insert({
        'id': const Uuid().v4(),
        'post_id': widget.postId,
        'user_id': user.id,
        'content': content,
      });
      _commentController.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding comment: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildAvatar(String? avatarUrl, String username, double radius) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.deepPurple.withOpacity(0.3),
      child: avatarUrl != null && avatarUrl.isNotEmpty
          ? ClipOval(
              child: Image.network(
                avatarUrl,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.deepPurple.withOpacity(0.5),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  print('Avatar load error: $error');
                  return Text(
                    username.isNotEmpty ? username[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: radius * 0.8,
                    ),
                  );
                },
              ),
            )
          : Text(
              username.isNotEmpty ? username[0].toUpperCase() : '?',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: radius * 0.8,
              ),
            ),
    );
  }

  String _formatTimeAgo(String? timestamp) {
    if (timestamp == null) return 'Just now';
    
    final now = DateTime.now();
    final time = DateTime.parse(timestamp).toLocal();
    final difference = now.difference(time);

    if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'now';
    }
  }

  Widget _buildPostCard() {
    if (_isPostLoading) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF11131B),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Colors.deepPurple),
        ),
      );
    }

    if (_post == null) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF11131B),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text(
            'Post not found',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF11131B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User info header
          Row(
            children: [
              _buildAvatar(_post!['avatar_url'], _post!['username'] ?? 'Unknown', 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _post!['username'] ?? 'Unknown',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      _formatTimeAgo(_post!['created_at']),
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Post content - Use caption field instead of content
          Text(
            _post!['caption']?.toString() ?? _post!['content']?.toString() ?? 'No content',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              height: 1.4,
            ),
          ),
          
          // Post image (if exists) - Use media_url instead of image_url
          if (_post!['media_url'] != null && _post!['media_url'].toString().isNotEmpty) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                _post!['media_url'],
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 200,
                    color: Colors.grey[800],
                    child: const Center(
                      child: Icon(Icons.broken_image, color: Colors.white54),
                    ),
                  );
                },
              ),
            ),
          ],
          
          const SizedBox(height: 16),
          
          // Engagement stats
          Row(
            children: [
              const Icon(Icons.favorite_border, color: Colors.white54, size: 20),
              const SizedBox(width: 6),
              Text(
                '${_post!['likes_count'] ?? 0}',
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(width: 24),
              const Icon(Icons.chat_bubble_outline, color: Colors.white54, size: 20),
              const SizedBox(width: 6),
              Text(
                '${_comments.length}',
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          const Divider(color: Colors.white24, thickness: 0.5),
          const SizedBox(height: 12),
          
          // "Replying to" indicator
          Row(
            children: [
              const Text(
                'Replying to ',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
              Text(
                '@${_post!['username'] ?? 'Unknown'}',
                style: const TextStyle(
                  color: Colors.deepPurple,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comments', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0B0D17),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      backgroundColor: const Color(0xFF0B0D17),
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                // Post at the top
                SliverToBoxAdapter(
                  child: _buildPostCard(),
                ),
                
                // Comments section
                if (_isLoading)
                  const SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(color: Colors.deepPurple),
                      ),
                    ),
                  )
                else if (_comments.isEmpty)
                  const SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'No comments yet. Be the first to comment!',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final comment = _comments[index];
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF11131B),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Comment header with user info
                              Row(
                                children: [
                                  _buildAvatar(comment['avatar_url'], comment['username'] ?? 'Unknown', 18),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          comment['username'] ?? 'Unknown',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                        Text(
                                          _formatTimeAgo(comment['created_at']),
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Comment content
                              Text(
                                comment['content'] ?? '',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      childCount: _comments.length,
                    ),
                  ),
              ],
            ),
          ),
          
          // Comment input section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF11131B),
              border: Border(top: BorderSide(color: Colors.white24, width: 0.5)),
            ),
            child: SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildAvatar(
                    supabase.auth.currentUser?.userMetadata?['avatar_url'],
                    supabase.auth.currentUser?.userMetadata?['username'] ?? 'User',
                    18
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1D29),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white24, width: 0.5),
                      ),
                      child: TextField(
                        controller: _commentController,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        maxLines: null,
                        decoration: const InputDecoration(
                          hintText: 'Tweet your reply...',
                          hintStyle: TextStyle(color: Colors.white60, fontSize: 16),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _addComment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Reply',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}