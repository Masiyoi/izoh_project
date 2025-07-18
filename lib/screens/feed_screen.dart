import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:unic_connect/models/post_model.dart';
import 'package:unic_connect/screens/create_post_screen.dart';
import 'package:unic_connect/services/post_service.dart';
import 'package:unic_connect/widgets/video_player_widget.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  late Future<List<PostModel>> _postsFuture;
  late AnimationController _fabAnimationController;
  late Animation<double> _fabAnimation;
  final ScrollController _scrollController = ScrollController();
  bool _isScrollingUp = false;
  double _lastScrollPosition = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _postsFuture = _fetchPosts();
    _setupAnimations();
    _setupScrollListener();
  }

  void _setupAnimations() {
    _fabAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fabAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _fabAnimationController,
        curve: Curves.easeInOut,
      ),
    );
    _fabAnimationController.forward();
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      final currentPosition = _scrollController.position.pixels;
      final isScrollingUp = currentPosition < _lastScrollPosition;

      if (isScrollingUp != _isScrollingUp) {
        setState(() {
          _isScrollingUp = isScrollingUp;
        });

        if (isScrollingUp) {
          _fabAnimationController.forward();
        } else {
          _fabAnimationController.reverse();
        }
      }
      _lastScrollPosition = currentPosition;
    });
  }

  Future<List<PostModel>> _fetchPosts() async {
    try {
      return await Provider.of<PostService>(context, listen: false).getPosts();
    } catch (e) {
      debugPrint('Error fetching posts: $e');
      rethrow;
    }
  }

  Future<void> _refreshPosts() async {
    try {
      final posts = await _fetchPosts();
      if (mounted) {
        setState(() {
          _postsFuture = Future.value(posts);
        });
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Failed to refresh posts');
      }
    }
  }

  Future<void> _navigateToCreatePost() async {
    _fabAnimationController.reverse();
    final result = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const CreatePostScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeInOutCubic;

          var tween = Tween(begin: begin, end: end).chain(
            CurveTween(curve: curve),
          );

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );

    _fabAnimationController.forward();

    if (result == true) {
      await _refreshPosts();
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade400,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }

  @override
  void dispose() {
    _fabAnimationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Feed', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 24)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade600],
            ),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.refresh, size: 20),
              ),
              onPressed: _refreshPosts,
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              isDark ? Colors.grey.shade900 : Colors.grey.shade50,
              isDark ? Colors.black : Colors.white,
            ],
          ),
        ),
        child: FutureBuilder<List<PostModel>>(
          future: _postsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingWidget();
            }
            if (snapshot.hasError) {
              return _ErrorWidget(
                error: snapshot.error.toString(),
                onRetry: _refreshPosts,
              );
            }
            final posts = snapshot.data ?? [];
            if (posts.isEmpty) {
              return const _EmptyStateWidget();
            }
            return RefreshIndicator(
              onRefresh: _refreshPosts,
              color: Colors.deepPurple,
              backgroundColor: theme.cardColor,
              child: ListView.builder(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(top: kToolbarHeight + 60, bottom: 100),
                itemCount: posts.length,
                itemBuilder: (context, index) {
                  return TweenAnimationBuilder<double>(
                    duration: Duration(milliseconds: 300 + (index * 100)),
                    tween: Tween(begin: 0.0, end: 1.0),
                    curve: Curves.easeOutBack,
                    builder: (context, value, child) {
                      return Transform.translate(
                        offset: Offset(0, 50 * (1 - value)),
                        child: Opacity(
                          opacity: value,
                          child: _PostCard(
                            post: posts[index],
                            formatTimestamp: _formatTimestamp,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            );
          },
        ),
      ),
      floatingActionButton: ScaleTransition(
        scale: _fabAnimation,
        child: FloatingActionButton.extended(
          onPressed: _navigateToCreatePost,
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          elevation: 8,
          label: const Text('Create Post', style: TextStyle(fontWeight: FontWeight.w600)),
          icon: const Icon(Icons.add_rounded),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

class _PostCard extends StatelessWidget {
  final PostModel post;
  final String Function(DateTime) formatTimestamp;

  const _PostCard({required this.post, required this.formatTimestamp});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        if (post.imageUrl != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => Scaffold(
                backgroundColor: Colors.black,
                appBar: AppBar(backgroundColor: Colors.transparent),
                body: Center(
                  child: Hero(
                    tag: post.id,
                    child: post.mediaType == 'video'
                        ? VideoPlayerWidget(videoUrl: post.imageUrl!)
                        : Image.network(post.imageUrl!, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          color: isDark ? Colors.grey.shade800 : Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (post.caption != null && post.caption!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(post.caption!, style: theme.textTheme.bodyLarge),
                ),
              if (post.imageUrl != null)
                Hero(
                  tag: post.id,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    child: post.mediaType == 'video'
                        ? VideoPlayerWidget(videoUrl: post.imageUrl!)
                        : Image.network(post.imageUrl!, fit: BoxFit.cover, width: double.infinity, height: 250),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Text(formatTimestamp(post.timestamp), style: theme.textTheme.bodySmall),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.favorite_border), onPressed: () {}),
                    IconButton(icon: const Icon(Icons.chat_bubble_outline), onPressed: () {}),
                    IconButton(icon: const Icon(Icons.share), onPressed: () {}),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingWidget extends StatelessWidget {
  const _LoadingWidget();
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

class _ErrorWidget extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorWidget({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Text(error));
}

class _EmptyStateWidget extends StatelessWidget {
  const _EmptyStateWidget();
  @override
  Widget build(BuildContext context) => const Center(child: Text('No posts yet'));
}
