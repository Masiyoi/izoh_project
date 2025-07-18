import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class ProfileScreen extends StatefulWidget {
  final String? userId; // Optional: if viewing another user's profile
  
  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with TickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  
  User? _currentUser;
  String? _profileImageUrl;
  String _userBio = '';
  String _displayName = '';
  int _postsCount = 0;
  int _followersCount = 0;
  int _followingCount = 0;
  String _email = '';
  bool _isOwnProfile = true;
  bool _isFollowing = false;
  bool _isEditingBio = false;
  // ignore: unused_field
  bool _isLoading = false;

  final TextEditingController _bioController = TextEditingController();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    _tabController = TabController(length: 3, vsync: this);
    _isOwnProfile = widget.userId == null || widget.userId == _currentUser?.uid;
    
    if (_currentUser != null) {
      _loadUserProfile();
      if (!_isOwnProfile) {
        _checkFollowingStatus();
      }
    }
  }

  @override
  void dispose() {
    _bioController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    if (_currentUser == null) return;

    setState(() => _isLoading = true);

    try {
      String targetUserId = widget.userId ?? _currentUser!.uid;
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(targetUserId).get();

      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        setState(() {
          _profileImageUrl = data['profileImageUrl'];
          _userBio = data['bio'] ?? 'No bio yet.';
          _displayName = data['displayName'] ?? 'Unknown User';
          _email = data['email'] ?? '';
          _postsCount = data['postsCount'] ?? 0;
          _followersCount = data['followersCount'] ?? 0;
          _followingCount = data['followingCount'] ?? 0;
          _bioController.text = _userBio;
        });
      }
    } catch (e) {
      _showErrorSnackBar('Failed to load profile: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _checkFollowingStatus() async {
    if (_currentUser == null || widget.userId == null) return;

    try {
      DocumentSnapshot followDoc = await _firestore
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('following')
          .doc(widget.userId)
          .get();

      setState(() {
        _isFollowing = followDoc.exists;
      });
    } catch (e) {
        debugPrint('Error checking follow status: $e');
    }
  }

  Future<void> _toggleFollow() async {
    if (_currentUser == null || widget.userId == null) return;

    setState(() => _isLoading = true);

    try {
      final batch = _firestore.batch();
      
      if (_isFollowing) {
        // Unfollow
        batch.delete(_firestore
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('following')
            .doc(widget.userId));
        
        batch.delete(_firestore
            .collection('users')
            .doc(widget.userId!)
            .collection('followers')
            .doc(_currentUser!.uid));

        batch.update(_firestore.collection('users').doc(_currentUser!.uid), {
          'followingCount': FieldValue.increment(-1)
        });

        batch.update(_firestore.collection('users').doc(widget.userId!), {
          'followersCount': FieldValue.increment(-1)
        });

        setState(() {
          _isFollowing = false;
          _followersCount--;
        });
      } else {
        // Follow
        batch.set(_firestore
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('following')
            .doc(widget.userId), {
          'followedAt': FieldValue.serverTimestamp(),
          'userId': widget.userId,
          'displayName': _displayName,
          'profileImageUrl': _profileImageUrl,
        });

        batch.set(_firestore
            .collection('users')
            .doc(widget.userId!)
            .collection('followers')
            .doc(_currentUser!.uid), {
          'followedAt': FieldValue.serverTimestamp(),
          'userId': _currentUser!.uid,
          'displayName': _currentUser!.displayName,
          'profileImageUrl': _currentUser!.photoURL,
        });

        batch.update(_firestore.collection('users').doc(_currentUser!.uid), {
          'followingCount': FieldValue.increment(1)
        });

        batch.update(_firestore.collection('users').doc(widget.userId!), {
          'followersCount': FieldValue.increment(1)
        });

        setState(() {
          _isFollowing = true;
          _followersCount++;
        });
      }

      await batch.commit();
    } catch (e) {
      _showErrorSnackBar('Failed to update follow status: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    if (!_isOwnProfile) return;

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );

      if (image != null) {
        setState(() => _isLoading = true);

        String downloadUrl;

        if (kIsWeb) {
          // Web: Use bytes directly
          final bytes = await image.readAsBytes();
          final ref = _storage.ref().child('profile_pictures/${_currentUser!.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg');
          final uploadTask = ref.putData(bytes);
          final snapshot = await uploadTask;
          downloadUrl = await snapshot.ref.getDownloadURL();
        } else {
          // Mobile: Use File
          File imageFile = File(image.path);
          String fileName = 'profile_pictures/${_currentUser!.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
          UploadTask uploadTask = _storage.ref().child(fileName).putFile(imageFile);
          TaskSnapshot snapshot = await uploadTask;
          downloadUrl = await snapshot.ref.getDownloadURL();
        }

        await _firestore.collection('users').doc(_currentUser!.uid).update({
          'profileImageUrl': downloadUrl,
        });

        // Force reload user profile from Firestore
        await _loadUserProfile();

        _showSuccessSnackBar('Profile picture updated!');
      }
    } catch (e) {
      _showErrorSnackBar('Failed to upload picture: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveBio() async {
    if (!_isOwnProfile) return;

    setState(() => _isLoading = true);

    try {
      await _firestore.collection('users').doc(_currentUser!.uid).update({
        'bio': _bioController.text.trim(),
      });
      
      setState(() {
        _userBio = _bioController.text.trim();
        _isEditingBio = false;
      });
      
      _showSuccessSnackBar('Bio updated successfully!');
    } catch (e) {
      _showErrorSnackBar('Failed to update bio: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(
            child: Column(
              children: [
                _buildProfileHeader(),
                _buildActionButtons(),
                _buildTabBar(),
                _buildTabContent(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 100,
      floating: true,
      pinned: true,
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        if (_isOwnProfile) ...[
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.black87),
            onPressed: () {
              // Navigate to settings
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black87),
            onPressed: () async {
              await _auth.signOut();
              Navigator.of(context).pushReplacementNamed('/login');
            },
          ),
        ] else ...[
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black87),
            onPressed: () {
              // Show more options
            },
          ),
        ],
      ],
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        title: Text(
          _isOwnProfile ? 'My Profile' : _displayName,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              // Profile Picture
              Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey.shade300, width: 2),
                    ),
                    child: CircleAvatar(
                      radius: 45,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: _profileImageUrl != null
                          ? NetworkImage(_profileImageUrl!)
                          : null,
                      child: _profileImageUrl == null
                          ? Icon(Icons.person, size: 50, color: Colors.grey.shade400)
                          : null,
                    ),
                  ),
                  if (_isOwnProfile)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade600,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 20),
              
              // Stats
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatColumn('Posts', _postsCount),
                    _buildStatColumn('Followers', _followersCount),
                    _buildStatColumn('Following', _followingCount),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 15),
          
          // Name and Bio
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 5),
                if (_isEditingBio && _isOwnProfile)
                  TextFormField(
                    controller: _bioController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Write your bio...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  )
                else
                  Text(
                    _userBio,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                      height: 1.3,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, int count) {
    return GestureDetector(
      onTap: () {
        // Navigate to followers/following list
      },
      child: Column(
        children: [
          Text(
            count.toString(),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          if (_isOwnProfile) ...[
            Expanded(
              child: _isEditingBio
                  ? Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _saveBio,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade600,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Save'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _isEditingBio = false;
                                _bioController.text = _userBio;
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey.shade700,
                              side: BorderSide(color: Colors.grey.shade300),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                      ],
                    )
                  : OutlinedButton(
                      onPressed: () => setState(() => _isEditingBio = true),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black87,
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Edit Profile'),
                    ),
            ),
          ] else ...[
            Expanded(
              child: ElevatedButton(
                onPressed: _toggleFollow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isFollowing ? Colors.grey.shade300 : Colors.blue.shade600,
                  foregroundColor: _isFollowing ? Colors.black87 : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(_isFollowing ? 'Following' : 'Follow'),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: () {
                // Send message
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black87,
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Message'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: Colors.black87,
        unselectedLabelColor: Colors.grey.shade600,
        indicatorColor: Colors.blue.shade600,
        tabs: const [
          Tab(icon: Icon(Icons.grid_on), text: 'Posts'),
          Tab(icon: Icon(Icons.bookmark_border), text: 'Saved'),
          Tab(icon: Icon(Icons.person_pin), text: 'Tagged'),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    return Container(
      height: 400,
      color: Colors.white,
      child: TabBarView(
        controller: _tabController,
        children: [
          _buildPostsGrid(),
          _buildSavedGrid(),
          _buildTaggedGrid(),
        ],
      ),
    );
  }

  Widget _buildPostsGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _postsCount,
      itemBuilder: (context, index) {
        return Container(
          color: Colors.grey.shade200,
          child: const Center(
            child: Icon(Icons.image, color: Colors.grey),
          ),
        );
      },
    );
  }

  Widget _buildSavedGrid() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bookmark_border, size: 60, color: Colors.grey),
          SizedBox(height: 10),
          Text('No saved posts yet', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildTaggedGrid() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_pin_outlined, size: 60, color: Colors.grey),
          SizedBox(height: 10),
          Text('No tagged posts yet', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}