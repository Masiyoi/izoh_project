import 'package:flutter/material.dart';
import 'package:unic_connect/utils/supabase_client.dart';

class CommentCountWidget extends StatefulWidget {
  final String postId;
  final VoidCallback? onTap;

  const CommentCountWidget({
    super.key,
    required this.postId,
    this.onTap,
  });

  @override
  State<CommentCountWidget> createState() => _CommentCountWidgetState();
}

class _CommentCountWidgetState extends State<CommentCountWidget> {
  final supabase = SupabaseClientUtil.client;
  int _commentCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCommentCount();
    _setupRealtime();
  }

  Future<void> _loadCommentCount() async {
    try {
      final response = await supabase
          .from('comments')
          .select('id')
          .eq('post_id', widget.postId);
      
      if (mounted) {
        setState(() {
          _commentCount = response.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _setupRealtime() {
    supabase
        .channel('comments-count-${widget.postId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'comments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'post_id',
            value: widget.postId,
          ),
          callback: (payload) => _loadCommentCount(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'comments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'post_id',
            value: widget.postId,
          ),
          callback: (payload) => _loadCommentCount(),
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              color: Colors.white54,
              size: 18,
            ),
            const SizedBox(width: 4),
            _isLoading
                ? SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white54,
                    ),
                  )
                : Text(
                    _commentCount.toString(),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 14,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

// Usage example in your post card:
class PostEngagementRow extends StatelessWidget {
  final String postId;
  final int likesCount;
  final VoidCallback onCommentTap;
  final VoidCallback onLikeTap;

  const PostEngagementRow({
    super.key,
    required this.postId,
    required this.likesCount,
    required this.onCommentTap,
    required this.onLikeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Like button
        InkWell(
          onTap: onLikeTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.favorite_border,
                  color: Colors.white54,
                  size: 18,
                ),
                const SizedBox(width: 4),
                Text(
                  likesCount.toString(),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // Comment button with count
        CommentCountWidget(
          postId: postId,
          onTap: onCommentTap,
        ),
        
        // Share button (optional)
        InkWell(
          onTap: () {
            // Handle share
          },
          borderRadius: BorderRadius.circular(20),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Icon(
              Icons.share_outlined,
              color: Colors.white54,
              size: 18,
            ),
          ),
        ),
      ],
    );
  }
}