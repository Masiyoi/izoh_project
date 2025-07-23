import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  bool _isLoading = true;
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _loadComments();
    _setupRealtime();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() => _isLoading = true);
    try {
      final response = await supabase
          .from('comments')
          .select('''
            *,
            profiles(username)
          ''')
          .eq('post_id', widget.postId)
          .order('created_at', ascending: true);
      setState(() {
        _comments = response.map<Map<String, dynamic>>((comment) => {
              ...comment,
              'username': comment['profiles']['username'] ?? 'Unknown',
            }).toList();
        _isLoading = false;
      });
    } catch (e) {
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
          type: PostgresChangeFilterType.eq, // Required parameter
          column: 'post_id',
          value: widget.postId,
        ),
        callback: (payload) => _loadComments(),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comments'),
        backgroundColor: const Color(0xFF0B0D17),
      ),
      backgroundColor: const Color(0xFF0B0D17),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _comments.length,
                    itemBuilder: (context, index) {
                      final comment = _comments[index];
                      return Card(
                        color: const Color(0xFF11131B),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundImage: AssetImage('assets/default_avatar.png'),
                          ),
                          title: Text(
                            comment['username'],
                            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            comment['content'],
                            style: const TextStyle(color: Colors.white),
                          ),
                          trailing: Text(
                            comment['created_at'] != null
                                ? (DateTime.parse(comment['created_at']).toLocal()).toString().split('.')[0]
                                : 'Just now',
                            style: const TextStyle(color: Colors.white54),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    style: const TextStyle(color: Colors.white70),
                    decoration: const InputDecoration(
                      hintText: 'Add a comment...',
                      hintStyle: TextStyle(color: Colors.white60),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                      filled: true,
                      fillColor: Color(0xFF11131B),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.deepPurple),
                  onPressed: _addComment,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}