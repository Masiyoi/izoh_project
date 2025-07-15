import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:unic_connect/screens/communities_screen.dart';
import 'package:unic_connect/screens/messages_screen.dart';
import 'package:unic_connect/screens/profile_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:unic_connect/utils/supabase_client.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  File? _selectedImage;
  final TextEditingController _captionController = TextEditingController();
  bool _isPosting = false;
  List<Map<String, dynamic>> _posts = [];
  RealtimeChannel? _realtimeChannel;

  static const List<Widget> _pages = [
    SizedBox.shrink(),
    MessagesScreen(),
    CommunitiesScreen(),
    ProfileScreen(),
  ];

  static const List<IconData> _navIcons = [
    Icons.home_rounded,
    Icons.chat_rounded,
    Icons.groups_rounded,
    Icons.person_rounded,
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
    _loadPosts();
    _setupRealtime();
  }

  @override
  void dispose() {
    _captionController.dispose();
    _animationController.dispose();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _setupRealtime() async {
    _realtimeChannel = supabase.channel('public:posts-likes')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'posts',
        callback: (payload) => _loadPosts(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'likes',
        callback: (payload) => _loadPosts(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'likes',
        callback: (payload) => _loadPosts(),
      )
      ..subscribe();
  }

  Future<void> _pickImage() async {
    try {
      final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        final file = File(pickedFile.path);
        final fileSize = await file.length();
        if (fileSize > 5 * 1024 * 1024) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Image size must be less than 5MB'), backgroundColor: Colors.red),
          );
          return;
        }
        setState(() => _selectedImage = file);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _uploadPost() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _captionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a caption'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isPosting = true);
    String? imageUrl;

    try {
      if (_selectedImage != null) {
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_${user.uid}.jpg';
        final bytes = await _selectedImage!.readAsBytes();
        await supabase.storage.from('post-media').uploadBinary(
          fileName,
          bytes,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
        );
        imageUrl = supabase.storage.from('post-media').getPublicUrl(fileName);
      }

      await supabase.from('posts').insert({
        'user_id': user.uid,
        'caption': _captionController.text.trim(),
        'media_url': imageUrl,
        'created_at': DateTime.now().toIso8601String(),
      });

      _captionController.clear();
      setState(() => _selectedImage = null);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error posting: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isPosting = false);
    }
  }

  Future<void> _loadPosts() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    try {
      final response = await supabase
          .from('posts')
          .select('''
            id, user_id, caption, media_url, created_at, 
            profiles!left(username),
            likes!left(user_id)
          ''')
          .order('created_at', ascending: false);

      setState(() {
        _posts = response.map<Map<String, dynamic>>((post) {
          final likes = post['likes'] as List<dynamic>? ?? [];
          return {
            ...post,
            'like_count': likes.length,
            'is_liked': userId != null && likes.any((like) => like['user_id'] == userId),
            'profiles': post['profiles'] ?? {'username': 'Unknown'},
          };
        }).toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading posts: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _toggleLike(String postId, bool isLiked) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to like posts'), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      if (isLiked) {
        await supabase.from('likes').delete().match({'post_id': postId, 'user_id': userId});
      } else {
        await supabase.from('likes').insert({
          'post_id': postId,
          'user_id': userId,
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
        });
      }
      await _loadPosts();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating like: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildCreatePostCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF11131B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundImage: AssetImage('assets/default_avatar.png'),
                radius: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _captionController,
                  style: const TextStyle(color: Colors.white70),
                  decoration: const InputDecoration(
                    hintText: "What's on your mind?",
                    hintStyle: TextStyle(color: Colors.white60),
                    border: InputBorder.none,
                  ),
                  maxLines: null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_selectedImage != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(_selectedImage!, height: 180, fit: BoxFit.cover),
            ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                onPressed: _isPosting ? null : _pickImage,
                icon: const Icon(Icons.image, color: Colors.deepPurple),
              ),
              ElevatedButton(
                onPressed: _isPosting ? null : _uploadPost,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isPosting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Post'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> post, int index) {
    final username = post['profiles']['username'] ?? 'User';
    final isLiked = post['is_liked'] ?? false;
    final likeCount = post['like_count'] ?? 0;

    return Card(
      color: const Color(0xFF11131B),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundImage: AssetImage('assets/default_avatar.png'),
                ),
                const SizedBox(width: 10),
                Text(
                  username,
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (post['media_url'] != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  post['media_url'],
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.error, color: Colors.red),
                ),
              ),
            const SizedBox(height: 10),
            Text(
              post['caption'] ?? '',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border,
                    color: isLiked ? Colors.red : Colors.deepPurple,
                  ),
                  onPressed: () => _toggleLike(post['id'], isLiked),
                ),
                Text('$likeCount', style: const TextStyle(color: Colors.white54)),
                const SizedBox(width: 20),
                IconButton(
                  icon: const Icon(Icons.comment_outlined, color: Colors.white54),
                  onPressed: () {
                    // TODO: open comments section or modal
                  },
                ),
                const Text('0', style: TextStyle(color: Colors.white54)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0D17),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          "UNIC CONNECT",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: _selectedIndex == 0
                ? ListView(
                    padding: const EdgeInsets.only(bottom: 100),
                    children: [
                      _buildCreatePostCard(),
                      if (_posts.isEmpty)
                        const Center(child: CircularProgressIndicator(color: Colors.deepPurple)),
                      ..._posts.asMap().entries.map((entry) => _buildPostCard(entry.value, entry.key)),
                    ],
                  )
                : _pages[_selectedIndex],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF0B0D17),
        selectedItemColor: Colors.deepPurple,
        unselectedItemColor: Colors.white54,
        elevation: 10,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: List.generate(_navIcons.length, (index) {
          return BottomNavigationBarItem(
            icon: Icon(_navIcons[index]),
            label: ['Home', 'Messages', 'Groups', 'Profile'][index],
          );
        }),
      ),
    );
  }
}