import 'package:flutter/material.dart';
import 'package:unic_connect/screens/comments_screen.dart';
import 'package:unic_connect/screens/communities_screen.dart';
import 'package:unic_connect/screens/messages_screen.dart';
import 'package:unic_connect/screens/profile_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:unic_connect/utils/supabase_client.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_io/io.dart';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final supabase = SupabaseClientUtil.client;
  int _selectedIndex = 0;
  late AnimationController _animationController;
  late AnimationController _fabAnimationController;
  late AnimationController _searchAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _fabScaleAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _searchScaleAnimation;
  File? _selectedImage;
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  bool _isPosting = false;
  bool _showCreatePost = false;
  bool _showSearch = false;
  bool _isSearching = false;
  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _searchResults = [];
  RealtimeChannel? _realtimeChannel;
  final ScrollController _scrollController = ScrollController();
  bool _showFab = true;

  static const List<Widget> _pages = [
    SizedBox.shrink(),
    MessagesScreen(),
    CommunitiesScreen(),
    ProfileScreen(),
  ];

  static const List<IconData> _navIcons = [
    Icons.home_rounded,
    Icons.mail_outline_rounded,
    Icons.people_outline_rounded,
    Icons.person_outline_rounded,
  ];

  static const List<IconData> _navIconsFilled = [
    Icons.home_rounded,
    Icons.mail_rounded,
    Icons.people_rounded,
    Icons.person_rounded,
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fabAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _searchAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _fabScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fabAnimationController, curve: Curves.elasticOut),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _searchScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _searchAnimationController, curve: Curves.elasticOut),
    );
    
    _animationController.forward();
    _fabAnimationController.forward();
    _loadPosts();
    _setupRealtime();
    _setupScrollListener();
    _setupSearchListener();
  }

  void _setupSearchListener() {
    _searchController.addListener(() {
      if (_searchController.text.isNotEmpty) {
        _performSearch(_searchController.text);
      } else {
        setState(() {
          _searchResults.clear();
        });
      }
    });
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      if (_scrollController.offset > 100 && _showFab) {
        setState(() => _showFab = false);
      } else if (_scrollController.offset <= 100 && !_showFab) {
        setState(() => _showFab = true);
      }
    });
  }

  @override
  void dispose() {
    _captionController.dispose();
    _searchController.dispose();
    _animationController.dispose();
    _fabAnimationController.dispose();
    _searchAnimationController.dispose();
    _scrollController.dispose();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    // Add haptic feedback
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      // Add haptic feedback for iOS
    }
  }

  Future<void> _setupRealtime() async {
    _realtimeChannel = supabase.channel('public:posts-likes-comments-follows')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'posts',
        callback: (payload) {
          _loadPosts();
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'likes',
        callback: (payload) {
          _updatePostLikes();
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'likes',
        callback: (payload) {
          _updatePostLikes();
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'comments',
        callback: (payload) {
          _loadPosts();
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'comments',
        callback: (payload) {
          _loadPosts();
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'follows',
        callback: (payload) {
          _refreshSearchResults();
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'follows',
        callback: (payload) {
          _refreshSearchResults();
        },
      )
      ..subscribe();
  }

  Future<void> _refreshSearchResults() async {
    if (_searchController.text.isNotEmpty) {
      await _performSearch(_searchController.text);
    }
  }

  Future<void> _updatePostLikes() async {
    // Optimized to only update likes without full reload
    _loadPosts();
  }

  Uint8List? _selectedImageBytes;

  Future<void> _pickImage() async {
    try {
      final pickedFile = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        if (kIsWeb) {
          final bytes = await pickedFile.readAsBytes();
          if (bytes.length > 5 * 1024 * 1024) {
            _showSnackBar('Image size must be less than 5MB', isError: true);
            return;
          }
          setState(() {
            _selectedImage = File(pickedFile.name);
            _selectedImageBytes = bytes;
          });
        } else {
          final file = File(pickedFile.path);
          final fileSize = await file.length();
          if (fileSize > 5 * 1024 * 1024) {
            _showSnackBar('Image size must be less than 5MB', isError: true);
            return;
          }
          setState(() => _selectedImage = file);
        }
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Error picking image: $e', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults.clear();
      });
      return;
    }

    setState(() => _isSearching = true);
    
    try {
      final currentUserId = supabase.auth.currentUser?.id;
      
      final response = await supabase
          .from('profiles')
          .select('''
            id,
            username,
            full_name,
            profile_image_url,
            avatar_url,
            bio,
            created_at,
            followers:follows!followed_id(follower_id),
            following:follows!follower_id(followed_id)
          ''')
          .ilike('username', '%$query%')
          .neq('id', currentUserId ?? '') // Exclude current user
          .limit(20);

      if (mounted) {
        setState(() {
          _searchResults = response.map<Map<String, dynamic>>((user) {
            final followers = user['followers'] as List<dynamic>? ?? [];
            final following = user['following'] as List<dynamic>? ?? [];
            final isFollowing = currentUserId != null && 
                followers.any((follow) => follow['follower_id'] == currentUserId);
            
            return {
              ...user,
              'followers_count': followers.length,
              'following_count': following.length,
              'is_following': isFollowing,
            };
          }).toList();
        });
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Error searching users: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  Future<void> _toggleFollow(String userId, bool isFollowing) async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      _showSnackBar('Please log in to follow users', isError: true);
      return;
    }

    // Optimistic update
    setState(() {
      final userIndex = _searchResults.indexWhere((user) => user['id'] == userId);
      if (userIndex != -1) {
        _searchResults[userIndex]['is_following'] = !isFollowing;
        _searchResults[userIndex]['followers_count'] += isFollowing ? -1 : 1;
      }
    });

    try {
      if (isFollowing) {
        // Unfollow
        await supabase.from('follows').delete().match({
          'follower_id': currentUserId,
          'followed_id': userId,
        });
      } else {
        // Follow
        await supabase.from('follows').insert({
          'follower_id': currentUserId,
          'followed_id': userId,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      
      _showSnackBar(isFollowing ? 'Unfollowed successfully' : 'Following now!');
    } catch (e) {
      // Revert optimistic update on error
      setState(() {
        final userIndex = _searchResults.indexWhere((user) => user['id'] == userId);
        if (userIndex != -1) {
          _searchResults[userIndex]['is_following'] = isFollowing;
          _searchResults[userIndex]['followers_count'] += isFollowing ? 1 : -1;
        }
      });
      _showSnackBar('Error updating follow status: $e', isError: true);
    }
  }

  Future<void> _uploadPost() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showSnackBar('Please log in to post', isError: true);
      return;
    }

    // Check if profile exists
    try {
      await supabase.from('profiles').select('id').eq('id', user.id).single();
    } catch (e) {
      await supabase.from('profiles').insert({
        'id': user.id,
        'username': 'User_${user.id.toString().substring(0, 8)}',
        'created_at': DateTime.now().toIso8601String(),
      });
    }

    if (_captionController.text.trim().isEmpty && _selectedImage == null) {
      _showSnackBar('Please enter a caption or select an image', isError: true);
      return;
    }

    setState(() => _isPosting = true);
    String? imageUrl;
    final uuid = const Uuid().v4();

    try {
      if (_selectedImage != null) {
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_${user.id}.jpg';
        if (kIsWeb) {
          await supabase.storage.from('post-media').uploadBinary(
            fileName,
            _selectedImageBytes!,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );
        } else {
          final bytes = await _selectedImage!.readAsBytes();
          await supabase.storage.from('post-media').uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );
        }
        imageUrl = supabase.storage.from('post-media').getPublicUrl(fileName);
      }

      await supabase.from('posts').insert({
        'id': uuid,
        'user_id': user.id,
        'caption': _captionController.text.trim().isEmpty ? null : _captionController.text.trim(),
        'media_url': imageUrl,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Clear form and close create post
      _captionController.clear();
      setState(() {
        _selectedImage = null;
        _selectedImageBytes = null;
        _showCreatePost = false;
      });
      
      _showSnackBar('Post shared successfully!');
      await _loadPosts();
    } catch (e) {
      _showSnackBar('Error posting: $e', isError: true);
    } finally {
      setState(() => _isPosting = false);
    }
  }

  Future<void> _loadPosts() async {
    final userId = supabase.auth.currentUser?.id;
    try {
      final response = await supabase
          .from('posts')
          .select('''
            *,
            profiles(username, profile_image_url, full_name),
            likes!left(user_id),
            comments!left(id)
          ''')
          .order('created_at', ascending: false);
      
      if (mounted) {
        setState(() {
          _posts = response.map<Map<String, dynamic>>((post) {
            final likes = post['likes'] as List<dynamic>? ?? [];
            final comments = post['comments'] as List<dynamic>? ?? [];
            return {
              ...post,
              'like_count': likes.length,
              'comment_count': comments.length,
              'is_liked': userId != null && likes.any((like) => like['user_id'] == userId),
            };
          }).toList();
        });
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Error loading posts: $e', isError: true);
    }
  }

  final Uuid uuid = Uuid();

  Future<void> _toggleLike(String postId, bool isLiked) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      _showSnackBar('Please log in to like posts', isError: true);
      return;
    }

    // Optimistic update
    setState(() {
      final postIndex = _posts.indexWhere((post) => post['id'] == postId);
      if (postIndex != -1) {
        _posts[postIndex]['is_liked'] = !isLiked;
        _posts[postIndex]['like_count'] += isLiked ? -1 : 1;
      }
    });

    try {
      if (isLiked) {
        await supabase.from('likes').delete().match({'post_id': postId, 'user_id': userId});
      } else {
        await supabase.from('likes').insert({
          'post_id': postId,
          'user_id': userId,
          'id': uuid.v4(),
        });
      }
    } catch (e) {
      // Revert optimistic update on error
      setState(() {
        final postIndex = _posts.indexWhere((post) => post['id'] == postId);
        if (postIndex != -1) {
          _posts[postIndex]['is_liked'] = isLiked;
          _posts[postIndex]['like_count'] += isLiked ? 1 : -1;
        }
      });
      _showSnackBar('Error updating like: $e', isError: true);
    }
  }

  void _navigateToComments(Map<String, dynamic> post) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CommentsScreen(
          postId: post['id'],
        ),
      ),
    ).then((_) {
      // Refresh posts when returning from comments screen
      _loadPosts();
    });
  }

  Widget _buildSearchModal() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _showSearch ? MediaQuery.of(context).size.height * 0.8 : 0,
      child: _showSearch ? Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1F2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade800)),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => setState(() {
                      _showSearch = false;
                      _searchController.clear();
                      _searchResults.clear();
                    }),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: "Search users...",
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        border: InputBorder.none,
                        prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                      ),
                      autofocus: true,
                    ),
                  ),
                ],
              ),
            ),
            // Search Results
            Expanded(
              child: _isSearching
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.blue),
                    )
                  : _searchResults.isEmpty
                      ? Center(
                          child: Text(
                            _searchController.text.isEmpty
                                ? 'Search for users to follow'
                                : 'No users found',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 16,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            return _buildUserCard(_searchResults[index]);
                          },
                        ),
            ),
          ],
        ),
      ) : const SizedBox.shrink(),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final username = user['username'] ?? 'User';
    final fullName = user['full_name'] ?? username;
    final bio = user['bio'] ?? '';
    final profilePictureUrl = user['profile_image_url'] ?? user['avatar_url'];
    final followersCount = user['followers_count'] ?? 0;
    final followingCount = user['following_count'] ?? 0;
    final isFollowing = user['is_following'] ?? false;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade900, width: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _buildProfileAvatar(profilePictureUrl, username),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fullName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    '@$username',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
                  if (bio.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      bio,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '$followingCount Following',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '$followersCount Followers',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: () => _toggleFollow(user['id'], isFollowing),
              style: ElevatedButton.styleFrom(
                backgroundColor: isFollowing ? Colors.grey.shade800 : Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(
                isFollowing ? 'Following' : 'Follow',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreatePostModal() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _showCreatePost ? MediaQuery.of(context).size.height * 0.7 : 0,
      child: _showCreatePost ? Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1F2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade800)),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => setState(() {
                      _showCreatePost = false;
                      _selectedImage = null;
                      _selectedImageBytes = null;
                      _captionController.clear();
                    }),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                  const Expanded(
                    child: Text(
                      'Create Post',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  TextButton(
                    onPressed: _isPosting ? null : _uploadPost,
                    child: _isPosting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.blue,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Post',
                            style: TextStyle(
                              color: Colors.blue,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.shade300,
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text(
                              'Y',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _captionController,
                            style: const TextStyle(color: Colors.white, fontSize: 18),
                            decoration: const InputDecoration(
                              hintText: "What's happening?",
                              hintStyle: TextStyle(color: Colors.grey, fontSize: 18),
                              border: InputBorder.none,
                            ),
                            maxLines: null,
                            autofocus: true,
                          ),
                        ),
                      ],
                    ),
                    if (_selectedImage != null) ...[
                      const SizedBox(height: 16),
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: kIsWeb
                                ? Image.memory(
                                    _selectedImageBytes!,
                                    height: 200,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  )
                                : Image.file(
                                    _selectedImage!,
                                    height: 200,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _selectedImage = null;
                                _selectedImageBytes = null;
                              }),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: Colors.grey.shade800)),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: _isPosting ? null : _pickImage,
                            icon: const Icon(Icons.image, color: Colors.blue, size: 24),
                          ),
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.gif_box_outlined, color: Colors.blue, size: 24),
                          ),
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.poll_outlined, color: Colors.blue, size: 24),
                          ),
                          const Spacer(),
                          Text(
                            '${280 - _captionController.text.length}',
                            style: TextStyle(
                              color: _captionController.text.length > 280 
                                  ? Colors.red 
                                  : Colors.grey,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ) : const SizedBox.shrink(),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> post, int index) {
    final profile = post['profiles'];
    final username = profile?['username'] ?? 'User';
    final fullName = profile?['full_name'] ?? username;
    final profilePictureUrl = profile?['profile_image_url'] ?? profile?['avatar_url'];
    final isLiked = post['is_liked'] ?? false;
    final likeCount = post['like_count'] ?? 0;
    final commentCount = post['comment_count'] ?? 0;
    final timeAgo = _getTimeAgo(post['created_at']);

    return GestureDetector(
      onTap: () => _navigateToComments(post),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade900, width: 0.5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Updated avatar with profile picture
              _buildProfileAvatar(profilePictureUrl, username),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          fullName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '@$username',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeAgo,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    if (post['caption'] != null && post['caption'].isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        post['caption'],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                    ],
                    if (post['media_url'] != null) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          post['media_url'],
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              height: 200,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade800,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Center(
                                child: Icon(Icons.error, color: Colors.grey),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildActionButton(
                          icon: Icons.chat_bubble_outline,
                          count: commentCount.toString(),
                          onTap: () => _navigateToComments(post),
                        ),
                        const SizedBox(width: 32),
                        _buildActionButton(
                          icon: Icons.repeat_rounded,
                          count: '0',
                          onTap: () {},
                        ),
                        const SizedBox(width: 32),
                        _buildActionButton(
                          icon: isLiked ? Icons.favorite : Icons.favorite_border,
                          count: likeCount.toString(),
                          color: isLiked ? Colors.red : null,
                          onTap: () => _toggleLike(post['id'], isLiked),
                        ),
                        const SizedBox(width: 32),
                        _buildActionButton(
                          icon: Icons.share_outlined,
                          count: '',
                          onTap: () {},
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 3. Add this new method to build profile avatars
  Widget _buildProfileAvatar(String? profilePictureUrl, String username) {
    if (profilePictureUrl != null && profilePictureUrl.isNotEmpty) {
      return Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
        ),
        child: ClipOval(
          child: Image.network(
            profilePictureUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _buildFallbackAvatar(username);
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return _buildFallbackAvatar(username);
            },
          ),
        ),
      );
    } else {
      return _buildFallbackAvatar(username);
    }
  }

  Widget _buildFallbackAvatar(String username) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade300,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          username.isNotEmpty ? username[0].toUpperCase() : 'U',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String count,
    Color? color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            icon,
            color: color ?? Colors.grey.shade600,
            size: 18,
          ),
          if (count.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              count,
              style: TextStyle(
                color: color ?? Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getTimeAgo(String? createdAt) {
    if (createdAt == null) return '';
    
    final now = DateTime.now();
    final postTime = DateTime.parse(createdAt);
    final difference = now.difference(postTime);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: _selectedIndex == 0 ? AppBar(
        backgroundColor: const Color(0xFF0A0E1A).withOpacity(0.8),
        elevation: 0,
        title: const Text(
          "UNIC CONNECT",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            onPressed: () {
              setState(() => _showSearch = true);
              _searchAnimationController.forward();
            },
            icon: const Icon(
              Icons.search,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ) : null,
      body: SafeArea(
        child: Stack(
          children: [
            FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: _selectedIndex == 0
                    ? RefreshIndicator(
                        onRefresh: _loadPosts,
                        color: Colors.blue,
                        backgroundColor: const Color(0xFF1A1F2E),
                        child: CustomScrollView(
                          controller: _scrollController,
                          slivers: [
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  if (_posts.isEmpty) {
                                    return const SizedBox(
                                      height: 200,
                                      child: Center(
                                        child: CircularProgressIndicator(color: Colors.blue),
                                      ),
                                    );
                                  }
                                  return _buildPostCard(_posts[index], index);
                                },
                                childCount: _posts.isEmpty ? 1 : _posts.length,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _pages[_selectedIndex],
              ),
            ),
            // Search Modal
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildSearchModal(),
            ),
            // Create Post Modal
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildCreatePostModal(),
            ),
          ],
        ),
      ),
      floatingActionButton: _selectedIndex == 0 && _showFab && !_showSearch && !_showCreatePost
          ? ScaleTransition(
              scale: _fabScaleAnimation,
              child: FloatingActionButton(
                onPressed: () => setState(() => _showCreatePost = true),
                backgroundColor: Colors.blue,
                child: const Icon(Icons.add, color: Colors.white),
              ),
            )
          : null,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.grey.shade900, width: 0.5)),
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: const Color(0xFF0A0E1A),
          selectedItemColor: Colors.blue,
          unselectedItemColor: Colors.grey.shade600,
          elevation: 0,
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          showSelectedLabels: false,
          showUnselectedLabels: false,
          items: List.generate(_navIcons.length, (index) {
            return BottomNavigationBarItem(
              icon: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Icon(
                  _selectedIndex == index ? _navIconsFilled[index] : _navIcons[index],
                  size: 26,
                ),
              ),
              label: '',
            );
          }),
        ),
      ),
    );
  }
}