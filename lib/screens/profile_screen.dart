import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
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
    // Add a small delay to ensure the auth state is fully settled
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadUserProfile();
        if (!_isOwnProfile) {
          _checkFollowingStatus();
        }
        _setupRealtime();
      }
    });
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
// Add this method to your _ProfileScreenState class
Future<void> _createProfileIfNotExists() async {
  if (_currentUser == null) return;

  try {
    // Check if profile exists
    final existingProfile = await supabase
        .from('profiles')
        .select('id')
        .eq('id', _currentUser!.id)
        .maybeSingle()
        .timeout(const Duration(seconds: 10));

    if (existingProfile == null) {
      // Profile doesn't exist, create it
      print('Creating new profile for user: ${_currentUser!.id}');
      
      // Generate a default username from email or use UUID
      String defaultUsername = _generateDefaultUsername();
      
      // Ensure username is unique
      defaultUsername = await _ensureUniqueUsername(defaultUsername);
      
      await supabase.from('profiles').insert({
        'id': _currentUser!.id,
        'username': defaultUsername,
        'email': _currentUser!.email ?? '',
        'bio': '',
        'profile_image_url': null,
        'posts_count': 0,
        'followers_count': 0,
        'following_count': 0,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).timeout(const Duration(seconds: 15));
      
      print('Profile created successfully');
    }
  } catch (e) {
    print('Error in _createProfileIfNotExists: $e');
    // Don't throw here, let the app continue and show error in _loadUserProfile
  }
}

// Helper method to generate default username
String _generateDefaultUsername() {
  if (_currentUser?.email != null && _currentUser!.email!.isNotEmpty) {
    // Extract username from email (part before @)
    String emailUsername = _currentUser!.email!.split('@')[0];
    // Clean it up to match username requirements
    emailUsername = emailUsername.replaceAll(RegExp(r'[^a-zA-Z0-9._]'), '');
    
    if (emailUsername.length >= 3 && emailUsername.length <= 30) {
      return emailUsername;
    }
  }
  
  // Fallback: generate a random username
  final uuid = const Uuid().v4().replaceAll('-', '').substring(0, 8);
  return 'user_$uuid';
}

// Helper method to ensure username uniqueness
Future<String> _ensureUniqueUsername(String baseUsername) async {
  String username = baseUsername;
  int counter = 1;
  
  while (true) {
    try {
      final existingUser = await supabase
          .from('profiles')
          .select('id')
          .ilike('username', username)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));
      
      if (existingUser == null) {
        // Username is available
        return username;
      }
      
      // Username taken, try with counter
      username = '${baseUsername}_$counter';
      counter++;
      
      // Safety check to prevent infinite loop
      if (counter > 100) {
        final uuid = const Uuid().v4().replaceAll('-', '').substring(0, 6);
        return '${baseUsername}_$uuid';
      }
    } catch (e) {
      print('Error checking username uniqueness: $e');
      // Fallback with UUID
      final uuid = const Uuid().v4().replaceAll('-', '').substring(0, 6);
      return '${baseUsername}_$uuid';
    }
  }
}

// Update your _loadUserProfile method
Future<void> _loadUserProfile() async {
  if (_currentUser == null || _isLoading) return;

  setState(() => _isLoading = true);

  try {
    String targetUserId = widget.userId ?? _currentUser!.id;
    
    // If it's the current user's own profile, ensure profile exists first
    if (_isOwnProfile) {
      await _createProfileIfNotExists();
    }
    
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
        _usernameController.text = _displayName;
      });
    } else if (mounted) {
      // If profile still doesn't exist and it's not the current user's profile
      if (!_isOwnProfile) {
        _showErrorSnackBar('Profile not found');
      } else {
        // For own profile, try creating again with a different approach
        _showErrorSnackBar('Failed to create profile. Please try again.');
      }
    }
  } catch (e) {
    print('Error in _loadUserProfile: $e');
    if (mounted) {
      if (_isOwnProfile && e.toString().contains('unique')) {
        // Retry with different username
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          _loadUserProfile(); // Retry once
        }
      } else {
        _showErrorSnackBar('Failed to load profile');
      }
    }
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}

// Also update your initState method to handle the profile creation better
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

  // Updated _saveBio method with better error handling
Future<void> _saveBio() async {
  if (!_isOwnProfile || _isLoading) return;

  final newBio = _bioController.text.trim();
  if (newBio == _userBio) {
    setState(() => _isEditingBio = false);
    return;
  }

  setState(() => _isLoading = true);

  try {
    print('Attempting to update bio for user: ${_currentUser!.id}');
    print('New bio: $newBio');
    print('Current session: ${supabase.auth.currentSession?.accessToken != null ? "Valid" : "Invalid"}');
    
    // First, verify the profile exists
    final profileCheck = await supabase
        .from('profiles')
        .select('id, username')
        .eq('id', _currentUser!.id)
        .maybeSingle()
        .timeout(const Duration(seconds: 5));
    
    print('Profile check result: $profileCheck');
    
    if (profileCheck == null) {
      print('Profile not found, creating one first...');
      await _createProfileIfNotExists();
      
      // Wait a moment for the profile to be created
      await Future.delayed(const Duration(milliseconds: 500));
    }
    
    // Now attempt the update with more detailed error catching
    final updateResult = await supabase
        .from('profiles')
        .update({'bio': newBio, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', _currentUser!.id)
        .select()
        .timeout(const Duration(seconds: 10));
    
    print('Update result: $updateResult');
    
    if (mounted) {
      setState(() {
        _userBio = newBio;
        _isEditingBio = false;
      });
      
      _showSuccessSnackBar('Bio updated successfully!');
    }
  } on PostgrestException catch (e) {
    print('PostgrestException: ${e.message}');
    print('Error details: ${e.details}');
    print('Error hint: ${e.hint}');
    print('Error code: ${e.code}');
    
    if (mounted) {
      String errorMessage = 'Failed to update bio';
      if (e.message.contains('RLS')) {
        errorMessage = 'Permission denied. Please try signing in again.';
      } else if (e.message.contains('not found')) {
        errorMessage = 'Profile not found. Creating profile...';
        // Try to create profile and retry
        await _createProfileIfNotExists();
        if (mounted) {
          _saveBio(); // Retry once
        }
        return;
      }
      _showErrorSnackBar(errorMessage);
    }
  } catch (e) {
    print('General error updating bio: $e');
    print('Error type: ${e.runtimeType}');
    
    if (mounted) {
      String errorMessage = 'Failed to update bio';
      if (e.toString().contains('timeout')) {
        errorMessage = 'Update timed out. Please check your connection.';
      } else if (e.toString().contains('401') || e.toString().contains('403')) {
        errorMessage = 'Session expired. Please sign in again.';
      }
      _showErrorSnackBar(errorMessage);
    }
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}
 void _showErrorSnackBar(String message) {
  if (!mounted) return;
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: TextStyle(color: colorScheme.onError),
      ),
      backgroundColor: colorScheme.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

void _showSuccessSnackBar(String message) {
  if (!mounted) return;
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: TextStyle(color: colorScheme.onPrimary),
      ),
      backgroundColor: Colors.green.shade600, // Keep green for success
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

 // Updated build method to use theme colors
@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  
  return PopScope(
    canPop: !_isLoading,
    onPopInvoked: (didPop) {
      if (_isLoading && !didPop) {
        _showErrorSnackBar('Please wait for the profile to load...');
      }
    },
    child: Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: _isLoading && _displayName.isEmpty
          ? Center(
              child: CircularProgressIndicator(
                color: colorScheme.primary,
              ),
            )
          : CustomScrollView(
              slivers: [
                _buildSliverAppBar(),
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      _buildProfileHeader(),
                      _buildActionButtons(),
                      _buildTabBar(),
                    ],
                  ),
                ),
                // Use SliverFillRemaining instead of SizedBox for better scrolling
                SliverFillRemaining(
                  child: _buildTabContent(),
                ),
              ],
            ),
    ),
  );
}
// Updated SliverAppBar to use theme colors
Widget _buildSliverAppBar() {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  
  return SliverAppBar(
    expandedHeight: 100,
    floating: true,
    pinned: true,
    backgroundColor: theme.appBarTheme.backgroundColor ?? colorScheme.surface,
    elevation: theme.appBarTheme.elevation ?? 0,
    leading: IconButton(
      icon: Icon(
        Icons.arrow_back_ios, 
        color: theme.appBarTheme.iconTheme?.color ?? colorScheme.onSurface,
      ),
      onPressed: () => Navigator.pop(context),
    ),
    actions: [
      if (_isOwnProfile) ...[
        IconButton(
          icon: Icon(
            Icons.settings, 
            color: theme.appBarTheme.iconTheme?.color ?? colorScheme.onSurface,
          ),
          onPressed: () {
            // Navigate to settings
          },
        ),
        IconButton(
          icon: Icon(
            Icons.logout, 
            color: theme.appBarTheme.iconTheme?.color ?? colorScheme.onSurface,
          ),
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
          icon: Icon(
            Icons.more_vert, 
            color: theme.appBarTheme.iconTheme?.color ?? colorScheme.onSurface,
          ),
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
        style: theme.appBarTheme.titleTextStyle ?? TextStyle(
          color: colorScheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

// Updated profile header to use theme colors
Widget _buildProfileHeader() {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  
  return Container(
    color: theme.cardColor, // Use theme card color
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
                      color: colorScheme.outline, // Use theme outline color
                      width: 2,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 45,
                    backgroundColor: colorScheme.surfaceContainerHighest, // Use theme surface variant
                    backgroundImage: _profileImageUrl != null
                        ? NetworkImage(_profileImageUrl!)
                        : null,
                    child: _profileImageUrl == null
                        ? Icon(
                            Icons.person, 
                            size: 50, 
                            color: colorScheme.onSurfaceVariant, // Use theme on-surface variant
                          )
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
                          color: colorScheme.primary, // Use theme primary color
                          shape: BoxShape.circle,
                          border: Border.all(color: theme.cardColor, width: 2),
                        ),
                        child: Icon(
                          Icons.camera_alt,
                          color: colorScheme.onPrimary, // Use theme on-primary color
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
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurface, // Use theme text color
                      ),
                      decoration: InputDecoration(
                        labelText: 'Username',
                        labelStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        hintText: 'Enter your username',
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: colorScheme.outline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: colorScheme.primary),
                        ),
                        contentPadding: const EdgeInsets.all(12),
                        prefixText: '@',
                        prefixStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface,
                        ),
                      ),
                      onChanged: (value) {
                        if (_debounce?.isActive ?? false) _debounce!.cancel();
                        _debounce = Timer(const Duration(milliseconds: 500), () {
                          // Real-time username validation here if needed
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Username must be 3-30 characters, letters, numbers, dots, and underscores only',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Text(
                      '@$_displayName',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
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
                          color: colorScheme.onSurfaceVariant,
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
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Write your bio...',
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colorScheme.outline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colorScheme.primary),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                    counterStyle: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                GestureDetector(
                  onTap: _isOwnProfile && !_isLoading ? () => setState(() => _isEditingBio = true) : null,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      _userBio.isEmpty ? 'Add a bio...' : _userBio,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _userBio.isEmpty 
                          ? colorScheme.onSurfaceVariant.withOpacity(0.6)
                          : colorScheme.onSurface,
                        height: 1.3,
                        fontStyle: _userBio.isEmpty ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

// Updated stat column to use theme colors
Widget _buildStatColumn(String label, int count) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  
  return GestureDetector(
    onTap: () {
      // Navigate to followers/following list
    },
    child: Column(
      children: [
        Text(
          count.toString(),
          style: theme.textTheme.headlineSmall?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

// Updated action buttons to use theme colors
Widget _buildActionButtons() {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  
  return Container(
    color: theme.cardColor,
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
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            disabledBackgroundColor: colorScheme.surfaceContainerHighest,
                            disabledForegroundColor: colorScheme.onSurfaceVariant,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isLoading 
                            ? SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(colorScheme.onPrimary),
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
                            foregroundColor: colorScheme.onSurface,
                            disabledForegroundColor: colorScheme.onSurface.withOpacity(0.38),
                            side: BorderSide(color: colorScheme.outline),
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
                      foregroundColor: colorScheme.onSurface,
                      disabledForegroundColor: colorScheme.onSurface.withOpacity(0.38),
                      side: BorderSide(color: colorScheme.outline),
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
                backgroundColor: _isFollowing ? colorScheme.surfaceContainerHighest : colorScheme.primary,
                foregroundColor: _isFollowing ? colorScheme.onSurfaceVariant : colorScheme.onPrimary,
                disabledBackgroundColor: colorScheme.surfaceContainerHighest,
                disabledForegroundColor: colorScheme.onSurfaceVariant,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isLoading 
                ? SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(
                        _isFollowing ? colorScheme.onSurfaceVariant : colorScheme.onPrimary
                      ),
                    ),
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
              foregroundColor: colorScheme.onSurface,
              side: BorderSide(color: colorScheme.outline),
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

// Updated tab bar to use theme colors
Widget _buildTabBar() {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  
  return Container(
    color: theme.cardColor,
    child: TabBar(
      controller: _tabController,
      labelColor: colorScheme.primary,
      unselectedLabelColor: colorScheme.onSurfaceVariant,
      indicatorColor: colorScheme.primary,
      tabs: const [
        Tab(icon: Icon(Icons.grid_on), text: 'Posts'),
        Tab(icon: Icon(Icons.bookmark_border), text: 'Saved'),
        Tab(icon: Icon(Icons.person_pin), text: 'Tagged'),
      ],
    ),
  );
}
  Widget _buildTabContent() {
  final theme = Theme.of(context);
  
  return Container(
    color: theme.scaffoldBackgroundColor, // Use theme background instead of default
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

// Updated _buildPostsGrid with theme-aware containers
Widget _buildPostsGrid() {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  
  return Container(
    color: theme.scaffoldBackgroundColor, // Use theme background
    child: FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadPosts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              color: colorScheme.primary,
            ),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline, 
                  size: 60, 
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 10),
                Text(
                  'Failed to load posts', 
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }
        final posts = snapshot.data ?? [];
        if (posts.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.photo, 
                  size: 60, 
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 10),
                Text(
                  'No posts yet', 
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
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
                  border: Border.all(color: colorScheme.outline.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: post['media_url'] != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(
                          post['media_url'],
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: Center(
                              child: Icon(
                                Icons.broken_image, 
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              color: colorScheme.surfaceContainerHighest,
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: colorScheme.primary,
                                  value: loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                      : null,
                                ),
                              ),
                            );
                          },
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.image, 
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
              ),
            );
          },
        );
      },
    ),
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
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  
  return Container(
    color: theme.scaffoldBackgroundColor,
    child: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bookmark_border, 
            size: 60, 
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          Text(
            'No saved posts yet', 
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

// Updated _buildTaggedGrid with theme colors
Widget _buildTaggedGrid() {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  
  return Container(
    color: theme.scaffoldBackgroundColor,
    child: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_pin_outlined, 
            size: 60, 
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          Text(
            'No tagged posts yet', 
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}
}