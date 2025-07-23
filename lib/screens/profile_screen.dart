import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:uuid/uuid.dart';
import 'package:unic_connect/utils/supabase_client.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId; // Optional: if viewing another user's profile

  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with TickerProviderStateMixin {
  final supabase = SupabaseClientUtil.client;
  User? _currentUser;
  String? _profileImageUrl;
  String _userBio = '';
  String _displayName = '';
  int _postsCount = 0;
  int _followersCount = 0;
  int _followingCount = 0;
  bool _isOwnProfile = true;
  bool _isFollowing = false;
  bool _isEditingBio = false;
  bool _isLoading = false;
  // ignore: unused_field
  String _email = '';

  final TextEditingController _bioController = TextEditingController();
  late TabController _tabController;
  RealtimeChannel? _followChannel;
  RealtimeChannel? _postsChannel;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _currentUser = supabase.auth.currentUser;
    _tabController = TabController(length: 3, vsync: this);
    _isOwnProfile = widget.userId == null || widget.userId == _currentUser?.id;
    
    if (_currentUser != null) {
      _loadUserProfile();
      if (!_isOwnProfile) {
        _checkFollowingStatus();
      }
      _setupRealtime();
    } else {
      // Handle case where user is not authenticated
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/login');
        }
      });
    }
  }

 // Add these new variables to your _ProfileScreenState class
bool _isEditingUsername = false;
final TextEditingController _usernameController = TextEditingController();

// Add this to your dispose method
@override
void dispose() {
  _bioController.dispose();
  _usernameController.dispose(); // Add this line
  _tabController.dispose();
  _followChannel?.unsubscribe();
  _postsChannel?.unsubscribe();
  _debounce?.cancel();
  super.dispose();
}

// Add this method to validate username
bool _isValidUsername(String username) {
  if (username.isEmpty || username.length < 3) {
    return false;
  }
  if (username.length > 30) {
    return false;
  }
  // Allow only alphanumeric characters, underscores, and dots
  final RegExp usernameRegex = RegExp(r'^[a-zA-Z0-9._]+$');
  return usernameRegex.hasMatch(username);
}

// Add this method to check username availability
Future<bool> _isUsernameAvailable(String username) async {
  if (username.toLowerCase() == _displayName.toLowerCase()) {
    return true; // Same username, no need to check
  }
  
  try {
    final response = await supabase
        .rpc('is_username_available', params: {
          'new_username': username,
          'user_id': _currentUser!.id,
        })
        .timeout(const Duration(seconds: 5));
    
    return response as bool;
  } catch (e) {
    print('Error checking username availability: $e');
    // Fallback: check manually
    try {
      final existingUser = await supabase
          .from('profiles')
          .select('id')
          .ilike('username', username)
          .neq('id', _currentUser!.id)
          .maybeSingle();
      
      return existingUser == null;
    } catch (e) {
      print('Fallback username check failed: $e');
      return false;
    }
  }
}

// Add this method to save username
Future<void> _saveUsername() async {
  if (!_isOwnProfile || _isLoading) return;

  final newUsername = _usernameController.text.trim();
  
  // Validate username
  if (!_isValidUsername(newUsername)) {
    _showErrorSnackBar('Username must be 3-30 characters and contain only letters, numbers, dots, and underscores');
    return;
  }

  if (newUsername == _displayName) {
    // No changes made
    setState(() => _isEditingUsername = false);
    return;
  }

  setState(() => _isLoading = true);

  try {
    // Check if username is available
    final isAvailable = await _isUsernameAvailable(newUsername);
    if (!isAvailable) {
      _showErrorSnackBar('Username is already taken');
      return;
    }

    // Update username in database
    await supabase
        .from('profiles')
        .update({'username': newUsername})
        .eq('id', _currentUser!.id)
        .timeout(const Duration(seconds: 10));
    
    if (mounted) {
      setState(() {
        _displayName = newUsername;
        _isEditingUsername = false;
      });
      
      _showSuccessSnackBar('Username updated successfully!');
    }
  } catch (e) {
    print('Error updating username: $e');
    if (mounted) {
      String errorMessage = 'Failed to update username';
      if (e.toString().contains('unique')) {
        errorMessage = 'Username is already taken';
      }
      _showErrorSnackBar(errorMessage);
    }
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}

// Update your _loadUserProfile method to initialize the username controller
Future<void> _loadUserProfile() async {
  if (_currentUser == null || _isLoading) return;

  setState(() => _isLoading = true);

  try {
    String targetUserId = widget.userId ?? _currentUser!.id;
    
    final response = await supabase
        .from('profiles')
        .select('username, bio, profile_image_url, email, posts_count, followers_count, following_count')
        .eq('id', targetUserId)
        .maybeSingle()
        .timeout(const Duration(seconds: 10));

    if (response != null && mounted) {
      setState(() {
        _profileImageUrl = response['profile_image_url'];
        _userBio = response['bio'] ?? 'No bio yet.';
        _displayName = response['username'] ?? 'Unknown User';
        _email = response['email'] ?? '';
        _postsCount = (response['posts_count'] as int?) ?? 0;
        _followersCount = (response['followers_count'] as int?) ?? 0;
        _followingCount = (response['following_count'] as int?) ?? 0;
        _bioController.text = _userBio;
        _usernameController.text = _displayName; // Initialize username controller
      });
    } else if (mounted) {
      _showErrorSnackBar('Profile not found');
    }
  } catch (e) {
    print('Error in _loadUserProfile: $e');
    if (mounted) {
      _showErrorSnackBar('Failed to load profile');
    }
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}

// Update your _buildProfileHeader method to include username editing

  Future<void> _checkFollowingStatus() async {
    if (_currentUser == null || widget.userId == null) return;

    try {
      final response = await supabase
          .from('followers')
          .select('id')
          .eq('follower_id', _currentUser!.id)
          .eq('followed_id', widget.userId!)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));
      
      if (mounted) {
        setState(() {
          _isFollowing = response != null;
        });
      }
    } catch (e) {
      debugPrint('Error checking follow status: $e');
    }
  }

  Future<void> _toggleFollow() async {
    if (_currentUser == null || widget.userId == null || _isLoading) return;

    setState(() => _isLoading = true);

    try {
      if (_isFollowing) {
        await supabase
            .from('followers')
            .delete()
            .eq('follower_id', _currentUser!.id)
            .eq('followed_id', widget.userId!)
            .timeout(const Duration(seconds: 10));
        
        // Call RPC function if it exists, otherwise handle manually
        try {
          await supabase.rpc('decrement_follow_counts', params: {
            'follower_id': _currentUser!.id,
            'followed_id': widget.userId!,
          }).timeout(const Duration(seconds: 5));
        } catch (rpcError) {
          print('RPC function not available, updating counts manually');
          // Manual count update as fallback
        }
        
        if (mounted) {
          setState(() {
            _isFollowing = false;
            _followersCount = (_followersCount - 1).clamp(0, double.infinity).toInt();
          });
        }
      } else {
        await supabase.from('followers').insert({
          'id': const Uuid().v4(),
          'follower_id': _currentUser!.id,
          'followed_id': widget.userId!,
          'followed_at': DateTime.now().toIso8601String(),
        }).timeout(const Duration(seconds: 10));
        
        try {
          await supabase.rpc('increment_follow_counts', params: {
            'follower_id': _currentUser!.id,
            'followed_id': widget.userId!,
          }).timeout(const Duration(seconds: 5));
        } catch (rpcError) {
          print('RPC function not available, updating counts manually');
          // Manual count update as fallback
        }
        
        if (mounted) {
          setState(() {
            _isFollowing = true;
            _followersCount++;
          });
        }
      }
    } catch (e) {
      print('Error in _toggleFollow: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to update follow status');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

Future<bool> _isSessionValid() async {
  try {
    final session = supabase.auth.currentSession;
    if (session == null || session.isExpired) {
      return false;
    }
    
    // Test with a simple query to verify authentication
    await supabase
        .from('profiles')
        .select('id')
        .eq('id', _currentUser!.id)
        .single()
        .timeout(const Duration(seconds: 5));
    
    return true;
  } catch (e) {
    print('Session validation error: $e');
    return false;
  }
}

// Refresh the session
Future<bool> _refreshSession() async {
  try {
    final response = await supabase.auth.refreshSession();
    if (response.session != null) {
      setState(() {
        _currentUser = response.user;
      });
      return true;
    }
    return false;
  } catch (e) {
    print('Session refresh error: $e');
    return false;
  }
}

// Updated _pickImage method with authentication handling
Future<void> _pickImage() async {
  if (!_isOwnProfile || _isLoading) return;

  try {
    // First, verify the session is valid
    if (!await _isSessionValid()) {
      print('Session invalid, attempting to refresh...');
      
      // Try to refresh the session
      if (!await _refreshSession()) {
        // If refresh fails, redirect to login
        if (mounted) {
          _showErrorSnackBar('Session expired. Please sign in again.');
          Navigator.of(context).pushReplacementNamed('/login');
        }
        return;
      }
    }

    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 75,
    );

    if (image != null && mounted) {
      setState(() => _isLoading = true);

      // Generate a unique filename with proper extension
      final fileExtension = image.path.split('.').last.toLowerCase();
      final validExtensions = ['jpg', 'jpeg', 'png'];
      final ext = validExtensions.contains(fileExtension) ? fileExtension : 'jpg';
      final fileName = 'profile_pictures/${_currentUser!.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';

      try {
        // Verify we still have a valid session before upload
        final currentSession = supabase.auth.currentSession;
        if (currentSession == null || currentSession.isExpired) {
          throw Exception('Authentication expired during upload');
        }

        print('Attempting upload to: $fileName');
        print('User ID: ${_currentUser!.id}');
        print('Session valid: ${currentSession.accessToken.isNotEmpty}');

        // Delete old profile picture if exists
        if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
          try {
            final oldFileName = _extractFileNameFromUrl(_profileImageUrl!);
            if (oldFileName.isNotEmpty) {
              await supabase.storage
                  .from('profile-images')
                  .remove([oldFileName]);
            }
          } catch (e) {
            print('Could not delete old image: $e');
            // Continue with upload even if deletion fails
          }
        }

        // Upload new image
        if (kIsWeb) {
          final bytes = await image.readAsBytes();
          await supabase.storage
              .from('profile-images')
              .uploadBinary(
                fileName, 
                bytes,
                fileOptions: FileOptions(
                  contentType: _getContentType(ext),
                  upsert: true,
                ),
              )
              .timeout(const Duration(seconds: 30));
        } else {
          final file = File(image.path);
          
          // Verify file exists and is readable
          if (!await file.exists()) {
            throw Exception('Selected file does not exist');
          }
          
          await supabase.storage
              .from('profile-images')
              .upload(
                fileName, 
                file,
                fileOptions: FileOptions(
                  contentType: _getContentType(ext),
                  upsert: true,
                ),
              )
              .timeout(const Duration(seconds: 30));
        }

        print('Upload successful, getting public URL...');

        // Get the public URL
        final downloadUrl = supabase.storage
            .from('profile-images')
            .getPublicUrl(fileName);
        
        if (downloadUrl.isEmpty) {
          throw Exception('Failed to generate download URL');
        }

        print('Public URL generated: $downloadUrl');

        // Update the profile in database
        await supabase
            .from('profiles')
            .update({'profile_image_url': downloadUrl})
            .eq('id', _currentUser!.id)
            .timeout(const Duration(seconds: 10));

        print('Database updated successfully');

        // Reload profile to get updated data
        await _loadUserProfile();
        
        if (mounted) {
          _showSuccessSnackBar('Profile picture updated successfully!');
        }
        
      } catch (uploadError) {
        print('Upload error details: $uploadError');
        
        // Handle specific authentication errors
        if (uploadError.toString().contains('401') || 
            uploadError.toString().contains('403') ||
            uploadError.toString().contains('JWT') ||
            uploadError.toString().contains('unauthorized')) {
          
          // Try to refresh session one more time
          if (await _refreshSession()) {
            if (mounted) {
              _showErrorSnackBar('Session refreshed. Please try uploading again.');
            }
          } else {
            if (mounted) {
              _showErrorSnackBar('Authentication expired. Please sign in again.');
              Navigator.of(context).pushReplacementNamed('/login');
            }
          }
          return;
        }
        
        // Provide more specific error messages for other errors
        String errorMessage = 'Failed to upload picture';
        if (uploadError.toString().contains('timeout')) {
          errorMessage = 'Upload timed out. Please check your connection and try again.';
        } else if (uploadError.toString().contains('413')) {
          errorMessage = 'Image file is too large. Please select a smaller image.';
        } else if (uploadError.toString().contains('storage')) {
          errorMessage = 'Storage service unavailable. Please try again later.';
        }
        
        if (mounted) {
          _showErrorSnackBar(errorMessage);
        }
      }
    }
  } catch (e) {
    print('Image picker error: $e');
    if (mounted) {
      String errorMessage = 'Failed to select image';
      if (e.toString().contains('permission')) {
        errorMessage = 'Permission denied to access gallery';
      } else if (e.toString().contains('camera')) {
        errorMessage = 'Camera not available';
      }
      _showErrorSnackBar(errorMessage);
    }
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}

// Helper method to extract filename from URL
String _extractFileNameFromUrl(String url) {
  try {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments;
    if (segments.isNotEmpty) {
      return segments.last;
    }
  } catch (e) {
    print('Error extracting filename: $e');
  }
  return '';
}

// Helper method to get proper content type
String _getContentType(String extension) {
  switch (extension.toLowerCase()) {
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    default:
      return 'image/jpeg';
  }
}

  Future<void> _saveBio() async {
    if (!_isOwnProfile || _isLoading) return;

    final newBio = _bioController.text.trim();
    if (newBio == _userBio) {
      // No changes made
      setState(() => _isEditingBio = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await supabase
          .from('profiles')
          .update({'bio': newBio})
          .eq('id', _currentUser!.id)
          .timeout(const Duration(seconds: 10));
      
      if (mounted) {
        setState(() {
          _userBio = newBio;
          _isEditingBio = false;
        });
        
        _showSuccessSnackBar('Bio updated successfully!');
      }
    } catch (e) {
      print('Error updating bio: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to update bio');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _setupRealtime() {
    if (_currentUser == null) return;
    
    final targetUserId = widget.userId ?? _currentUser!.id;
    
    try {
      _followChannel = supabase.channel('follow-$targetUserId')
        ..onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'followers',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'followed_id',
            value: targetUserId,
          ),
          callback: (payload) {
            if (mounted) {
              if (!_isOwnProfile) _checkFollowingStatus();
              _loadUserProfile();
            }
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'followers',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'followed_id',
            value: targetUserId,
          ),
          callback: (payload) {
            if (mounted) {
              if (!_isOwnProfile) _checkFollowingStatus();
              _loadUserProfile();
            }
          },
        )
        ..subscribe();

      if (_isOwnProfile) {
        _postsChannel = supabase.channel('posts-${_currentUser!.id}')
          ..onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'posts',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: _currentUser!.id,
            ),
            callback: (payload) {
              if (mounted) {
                _loadUserProfile();
              }
            },
          )
          ..subscribe();
      }
    } catch (e) {
      print('Error setting up realtime: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isLoading,
      onPopInvoked: (didPop) {
        if (_isLoading && !didPop) {
          _showErrorSnackBar('Please wait for the profile to load...');
        }
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        body: _isLoading && _displayName.isEmpty
            ? const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
            : CustomScrollView(
                slivers: [
                  _buildSliverAppBar(),
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        _buildProfileHeader(),
                        _buildActionButtons(),
                        _buildTabBar(),
                        SizedBox(
                          height: 400,
                          child: _buildTabContent(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
              try {
                await supabase.auth.signOut();
                if (mounted) {
                  Navigator.of(context).pushReplacementNamed('/login');
                }
              } catch (e) {
                print('Error signing out: $e');
                if (mounted) {
                  _showErrorSnackBar('Failed to sign out');
                }
              }
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
            Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.grey.shade300,
                      width: 2,
                    ),
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
        Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Username section
              if (_isEditingUsername && _isOwnProfile)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        labelText: 'Username',
                        hintText: 'Enter your username',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        contentPadding: const EdgeInsets.all(12),
                        prefixText: '@',
                      ),
                      onChanged: (value) {
                        // Optional: Real-time validation feedback
                        if (_debounce?.isActive ?? false) _debounce!.cancel();
                        _debounce = Timer(const Duration(milliseconds: 500), () {
                          // You can add real-time username validation here
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Username must be 3-30 characters, letters, numbers, dots, and underscores only',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Text(
                      '@$_displayName',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    if (_isOwnProfile) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _isLoading ? null : () {
                          setState(() {
                            _isEditingUsername = true;
                            _usernameController.text = _displayName;
                          });
                        },
                        child: Icon(
                          Icons.edit,
                          size: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              const SizedBox(height: 10),
              
              // Bio section
              if (_isEditingBio && _isOwnProfile)
                TextFormField(
                  controller: _bioController,
                  maxLines: 3,
                  maxLength: 150,
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
                    color: Colors.grey.shade600,
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
            child: (_isEditingBio || _isEditingUsername)
                ? Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : () async {
                            if (_isEditingUsername) {
                              await _saveUsername();
                            }
                            if (_isEditingBio) {
                              await _saveBio();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade600,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isLoading 
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(Colors.white),
                                ),
                              )
                            : const Text('Save'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isLoading ? null : () {
                            setState(() {
                              _isEditingBio = false;
                              _isEditingUsername = false;
                              _bioController.text = _userBio;
                              _usernameController.text = _displayName;
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
                    onPressed: _isLoading ? null : () => setState(() => _isEditingBio = true),
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
              onPressed: _isLoading ? null : _toggleFollow,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isFollowing ? Colors.grey.shade300 : Colors.blue.shade600,
                foregroundColor: _isFollowing ? Colors.black87 : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isLoading 
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isFollowing ? 'Following' : 'Follow'),
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
    return TabBarView(
      controller: _tabController,
      children: [
        _buildPostsGrid(),
        _buildSavedGrid(),
        _buildTaggedGrid(),
      ],
    );
  }

  Widget _buildPostsGrid() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadPosts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 60, color: Colors.grey),
                SizedBox(height: 10),
                Text('Failed to load posts', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }
        final posts = snapshot.data ?? [];
        if (posts.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.photo, size: 60, color: Colors.grey),
                SizedBox(height: 10),
                Text('No posts yet', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(2),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          itemCount: posts.length,
          itemBuilder: (context, index) {
            final post = posts[index];
            return GestureDetector(
              onTap: () {
                // Navigate to post detail
              },
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: post['media_url'] != null
                    ? Image.network(
                        post['media_url'],
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(child: CircularProgressIndicator());
                        },
                      )
                    : const Center(child: Icon(Icons.image, color: Colors.grey)),
              ),
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadPosts() async {
    try {
      final response = await supabase
          .from('posts')
          .select('id, media_url, content, created_at')
          .eq('user_id', widget.userId ?? _currentUser!.id)
          .order('created_at', ascending: false)
          .limit(20)
          .timeout(const Duration(seconds: 10));
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error loading posts: $e');
      return [];
    }
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