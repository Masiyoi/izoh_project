// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart' as material;
import 'package:path/path.dart' as path_lib;
// Then use path_lib.context instead of just context when you need the path context
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;

class CommunitiesScreen extends material.StatelessWidget {
  const CommunitiesScreen({super.key});

  @override
  material.Widget build(material.BuildContext context) {
    return _CommunitiesScreenStateful();
  }
}

class _CommunitiesScreenStateful extends material.StatefulWidget {
  @override
  material.State<_CommunitiesScreenStateful> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends material.State<_CommunitiesScreenStateful> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _communities = [];
  List<Map<String, dynamic>> _userCommunities = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadCommunities();
  }

  Future<void> _loadCommunities() async {
    setState(() => _isLoading = true);

    try {
      final communitiesResponse = await _supabase
          .from('communities')
          .select('*')
          .order('created_at', ascending: false);

      final userCommunitiesResponse = await _supabase
          .from('community_members')
          .select('*, communities(*)')
          .eq('user_id', _supabase.auth.currentUser!.id);

      List<Map<String, dynamic>> communitiesWithCounts = [];
      for (var community in communitiesResponse) {
        final memberCountResponse = await _supabase
            .from('community_members')
            .select('id')
            .eq('community_id', community['id']);

        communitiesWithCounts.add({
          ...community,
          'member_count': memberCountResponse.length,
        });
      }

      setState(() {
        _communities = communitiesWithCounts;
        _userCommunities = List<Map<String, dynamic>>.from(userCommunitiesResponse);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackBar('Error loading communities: $e');
    }
  }

  Future<void> _createCommunity() async {
    final result = await material.showDialog<Map<String, String>>(
      context: context,
      builder: (context) => const _CreateCommunityDialog(),
    );

    if (result != null) {
      try {
        final response = await _supabase.from('communities').insert({
          'name': result['name'],
          'description': result['description'],
          'creator_id': _supabase.auth.currentUser!.id,
          'category': result['category'],
          'is_private': result['isPrivate'] == 'true',
        }).select().single();

        await _supabase.from('community_members').insert({
          'community_id': response['id'],
          'user_id': _supabase.auth.currentUser!.id,
          'role': 'admin',
        });

        _loadCommunities();
        _showSuccessSnackBar('Community created successfully!');
      } catch (e) {
        _showErrorSnackBar('Error creating community: $e');
      }
    }
  }

  Future<void> _joinCommunity(Map<String, dynamic> community) async {
    if (community['is_private'] == true) {
      await _requestToJoinPrivateCommunity(community);
    } else {
      try {
        await _supabase.from('community_members').insert({
          'community_id': community['id'],
          'user_id': _supabase.auth.currentUser!.id,
          'role': 'member',
        });

        _loadCommunities();
        _showSuccessSnackBar('Successfully joined community!');
      } catch (e) {
        _showErrorSnackBar('Error joining community: $e');
      }
    }
  }

  Future<void> _requestToJoinPrivateCommunity(Map<String, dynamic> community) async {
    final messageController = material.TextEditingController();

    final result = await material.showDialog<bool>(
      context: context,
      builder: (context) => material.AlertDialog(
        title: material.Text('Request to Join ${community['name']}'),
        backgroundColor: material.Theme.of(context).colorScheme.surface,
        content: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            material.Text(
              'This is a private community. Send a message to the admins:',
              style: material.Theme.of(context).textTheme.bodyMedium,
            ),
            const material.SizedBox(height: 16),
            material.TextField(
              controller: messageController,
              decoration: material.InputDecoration(
                labelText: 'Message (optional)',
                border: material.Theme.of(context).inputDecorationTheme.border ?? const material.OutlineInputBorder(),
                labelStyle: material.Theme.of(context).inputDecorationTheme.labelStyle,
                filled: material.Theme.of(context).inputDecorationTheme.filled,
                fillColor: material.Theme.of(context).inputDecorationTheme.fillColor,
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          material.TextButton(
            onPressed: () => material.Navigator.pop(context, false),
            child: material.Text(
              'Cancel',
              style: material.Theme.of(context).textTheme.labelLarge,
            ),
          ),
          material.ElevatedButton(
            onPressed: () => material.Navigator.pop(context, true),
            style: material.Theme.of(context).elevatedButtonTheme.style,
            child: const material.Text('Send Request'),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        await _supabase.from('community_join_requests').insert({
          'community_id': community['id'],
          'user_id': _supabase.auth.currentUser!.id,
          'message': messageController.text.trim(),
        });
        _showSuccessSnackBar('Join request sent!');
      } catch (e) {
        _showErrorSnackBar('Error sending request: $e');
      }
    }
  }

  Future<void> _leaveCommunity(String communityId) async {
    try {
      await _supabase
          .from('community_members')
          .delete()
          .eq('community_id', communityId)
          .eq('user_id', _supabase.auth.currentUser!.id);

      _loadCommunities();
      _showSuccessSnackBar('Successfully left community!');
    } catch (e) {
      _showErrorSnackBar('Error leaving community: $e');
    }
  }

  bool _isUserMember(String communityId) {
    return _userCommunities.any((uc) => uc['community_id'] == communityId);
  }

  List<Map<String, dynamic>> get _filteredCommunities {
    if (_searchQuery.isEmpty) return _communities;
    return _communities.where((community) {
      final name = community['name']?.toString().toLowerCase() ?? '';
      final description = community['description']?.toString().toLowerCase() ?? '';
      final query = _searchQuery.toLowerCase();
      return name.contains(query) || description.contains(query);
    }).toList();
  }

  void _showErrorSnackBar(String message) {
    material.ScaffoldMessenger.of(context).showSnackBar(
      material.SnackBar(
        content: material.Text(message),
        backgroundColor: material.Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    material.ScaffoldMessenger.of(context).showSnackBar(
      material.SnackBar(
        content: material.Text(message),
        backgroundColor: material.Theme.of(context).snackBarTheme.backgroundColor,
      ),
    );
  }

  void _openCommunityDetails(Map<String, dynamic> community) {
    material.Navigator.push(
      context,
      material.MaterialPageRoute(
        builder: (context) => CommunityDetailsScreen(community: community),
      ),
    );
  }

  @override
  material.Widget build(material.BuildContext context) {
    return material.Scaffold(
      backgroundColor: material.Theme.of(context).scaffoldBackgroundColor,
      appBar: material.AppBar(
        title: const material.Text('Communities'),
        backgroundColor: material.Theme.of(context).appBarTheme.backgroundColor,
        actions: [
          material.IconButton(
            icon: const material.Icon(material.Icons.add),
            onPressed: _createCommunity,
            tooltip: 'Create Community',
          ),
        ],
      ),
      body: material.Column(
        children: [
          material.Padding(
            padding: const material.EdgeInsets.all(16.0),
            child: material.TextField(
              decoration: material.InputDecoration(
                hintText: 'Search communities...',
                prefixIcon: const material.Icon(material.Icons.search),
                border: material.Theme.of(context).inputDecorationTheme.border ?? const material.OutlineInputBorder(),
                labelStyle: material.Theme.of(context).inputDecorationTheme.labelStyle,
                filled: material.Theme.of(context).inputDecorationTheme.filled,
                fillColor: material.Theme.of(context).inputDecorationTheme.fillColor,
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),
          material.Expanded(
            child: material.DefaultTabController(
              length: 2,
              child: material.Column(
                children: [
                  material.TabBar(
                    tabs: const [
                      material.Tab(text: 'All Communities'),
                      material.Tab(text: 'My Communities'),
                    ],
                    labelColor: material.Theme.of(context).textTheme.titleLarge?.color,
                    unselectedLabelColor: material.Theme.of(context).textTheme.labelMedium?.color,
                  ),
                  material.Expanded(
                    child: material.TabBarView(
                      children: [
                        _buildAllCommunitiesTab(),
                        _buildMyCommunitiesTab(),
                      ],
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

  material.Widget _buildAllCommunitiesTab() {
    if (_isLoading) {
      return const material.Center(child: material.CircularProgressIndicator());
    }

    if (_filteredCommunities.isEmpty) {
      return material.Center(
        child: material.Text(
          'No communities found',
          style: material.Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return material.ListView.builder(
      padding: const material.EdgeInsets.all(16),
      itemCount: _filteredCommunities.length,
      itemBuilder: (context, index) {
        final community = _filteredCommunities[index];
        final isMember = _isUserMember(community['id']);
        final memberCount = community['member_count'] ?? 0;
        final isPrivate = community['is_private'] == true;

        return material.Card(
          margin: const material.EdgeInsets.only(bottom: 12),
          color: material.Theme.of(context).colorScheme.surface,
          child: material.ListTile(
            leading: material.CircleAvatar(
              backgroundColor: isPrivate ? material.Colors.orange : material.Colors.blue,
              child: material.Icon(
                isPrivate ? material.Icons.lock : material.Icons.public,
                color: material.Colors.white,
              ),
            ),
            title: material.Text(
              community['name'] ?? 'Unknown Community',
              style: material.Theme.of(context).textTheme.titleLarge,
            ),
            subtitle: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.start,
              children: [
                material.Text(
                  community['description'] ?? 'No description',
                  style: material.Theme.of(context).textTheme.bodyMedium,
                ),
                const material.SizedBox(height: 4),
                material.Row(
                  children: [
                    material.Icon(material.Icons.people, size: 16, color: material.Theme.of(context).iconTheme.color),
                    const material.SizedBox(width: 4),
                    material.Text('$memberCount members', style: material.Theme.of(context).textTheme.labelMedium),
                    const material.SizedBox(width: 12),
                    if (community['category'] != null) ...[
                      material.Icon(material.Icons.category, size: 16, color: material.Theme.of(context).iconTheme.color),
                      const material.SizedBox(width: 4),
                      material.Text(community['category'], style: material.Theme.of(context).textTheme.labelMedium),
                    ],
                    if (isPrivate) ...[
                      const material.SizedBox(width: 12),
                      const material.Icon(material.Icons.lock, size: 16, color: material.Colors.orange),
                      const material.SizedBox(width: 4),
                      const material.Text('Private', style: material.TextStyle(color: material.Colors.orange)),
                    ],
                  ],
                ),
              ],
            ),
            trailing: material.Row(
              mainAxisSize: material.MainAxisSize.min,
              children: [
                if (isMember) ...[
                  material.IconButton(
                    icon: const material.Icon(material.Icons.open_in_new),
                    onPressed: () => _openCommunityDetails(community),
                    tooltip: 'Open Community',
                  ),
                  material.IconButton(
                    icon: const material.Icon(material.Icons.exit_to_app, color: material.Colors.red),
                    onPressed: () => _leaveCommunity(community['id']),
                    tooltip: 'Leave Community',
                  ),
                ] else ...[
                  material.ElevatedButton(
                    onPressed: () => _joinCommunity(community),
                    style: material.Theme.of(context).elevatedButtonTheme.style?.copyWith(
                          backgroundColor: material.WidgetStateProperty.all(isPrivate ? material.Colors.orange : material.Colors.blue),
                        ),
                    child: material.Text(isPrivate ? 'Request' : 'Join'),
                  ),
                ],
              ],
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }

  material.Widget _buildMyCommunitiesTab() {
    if (_isLoading) {
      return const material.Center(child: material.CircularProgressIndicator());
    }

    if (_userCommunities.isEmpty) {
      return material.Center(
        child: material.Column(
          mainAxisAlignment: material.MainAxisAlignment.center,
          children: [
            material.Icon(material.Icons.group_off, size: 64, color: material.Theme.of(context).iconTheme.color),
            const material.SizedBox(height: 16),
            material.Text(
              'You haven\'t joined any communities yet',
              style: material.Theme.of(context).textTheme.bodyMedium,
            ),
            const material.SizedBox(height: 8),
            material.Text(
              'Join some communities to see them here!',
              style: material.Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return material.ListView.builder(
      padding: const material.EdgeInsets.all(16),
      itemCount: _userCommunities.length,
      itemBuilder: (context, index) {
        final userCommunity = _userCommunities[index];
        final community = userCommunity['communities'];

        return material.Card(
          margin: const material.EdgeInsets.only(bottom: 12),
          color: material.Theme.of(context).colorScheme.surface,
          child: material.ListTile(
            leading: material.CircleAvatar(
              backgroundColor: material.Colors.green,
              child: material.Text(
                community['name']?[0]?.toUpperCase() ?? 'C',
                style: const material.TextStyle(color: material.Colors.white, fontWeight: material.FontWeight.bold),
              ),
            ),
            title: material.Text(
              community['name'] ?? 'Unknown Community',
              style: material.Theme.of(context).textTheme.titleLarge,
            ),
            subtitle: material.Text(
              community['description'] ?? 'No description',
              style: material.Theme.of(context).textTheme.bodyMedium,
            ),
            trailing: material.IconButton(
              icon: const material.Icon(material.Icons.arrow_forward_ios),
              onPressed: () => _openCommunityDetails(community),
            ),
          ),
        );
      },
    );
  }
}

class _CreateCommunityDialog extends material.StatefulWidget {
  const _CreateCommunityDialog();

  @override
  material.State<_CreateCommunityDialog> createState() => _CreateCommunityDialogState();
}

class _CreateCommunityDialogState extends material.State<_CreateCommunityDialog> {
  final _nameController = material.TextEditingController();
  final _descriptionController = material.TextEditingController();
  String _selectedCategory = 'General';
  bool _isPrivate = false;

  final List<String> _categories = [
    'General',
    'Technology',
    'Sports',
    'Education',
    'Entertainment',
    'Business',
    'Health',
    'Gaming',
    'Art',
    'Music',
  ];

  @override
  material.Widget build(material.BuildContext context) {
    return material.AlertDialog(
      backgroundColor: material.Theme.of(context).colorScheme.surface,
      title: material.Text('Create Community', style: material.Theme.of(context).textTheme.titleLarge),
      content: material.SingleChildScrollView(
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            material.TextField(
              controller: _nameController,
              decoration: material.InputDecoration(
                labelText: 'Community Name',
                border: material.Theme.of(context).inputDecorationTheme.border ?? const material.OutlineInputBorder(),
                labelStyle: material.Theme.of(context).inputDecorationTheme.labelStyle,
                filled: material.Theme.of(context).inputDecorationTheme.filled,
                fillColor: material.Theme.of(context).inputDecorationTheme.fillColor,
              ),
            ),
            const material.SizedBox(height: 16),
            material.TextField(
              controller: _descriptionController,
              decoration: material.InputDecoration(
                labelText: 'Description',
                border: material.Theme.of(context).inputDecorationTheme.border ?? const material.OutlineInputBorder(),
                labelStyle: material.Theme.of(context).inputDecorationTheme.labelStyle,
                filled: material.Theme.of(context).inputDecorationTheme.filled,
                fillColor: material.Theme.of(context).inputDecorationTheme.fillColor,
              ),
              maxLines: 3,
            ),
            const material.SizedBox(height: 16),
            material.DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: material.InputDecoration(
                labelText: 'Category',
                border: material.Theme.of(context).inputDecorationTheme.border ?? const material.OutlineInputBorder(),
                labelStyle: material.Theme.of(context).inputDecorationTheme.labelStyle,
                filled: material.Theme.of(context).inputDecorationTheme.filled,
                fillColor: material.Theme.of(context).inputDecorationTheme.fillColor,
              ),
              items: _categories.map((category) {
                return material.DropdownMenuItem(
                  value: category,
                  child: material.Text(category),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedCategory = value!);
              },
            ),
            const material.SizedBox(height: 16),
            material.SwitchListTile(
              title: material.Text('Private Community', style: material.Theme.of(context).textTheme.titleLarge),
              subtitle: material.Text('Requires approval to join', style: material.Theme.of(context).textTheme.bodyMedium),
              value: _isPrivate,
              onChanged: (value) {
                setState(() => _isPrivate = value);
              },
            ),
          ],
        ),
      ),
      actions: [
        material.TextButton(
          onPressed: () => material.Navigator.pop(context),
          child: material.Text('Cancel', style: material.Theme.of(context).textTheme.labelLarge),
        ),
        material.ElevatedButton(
          onPressed: () {
            if (_nameController.text.trim().isNotEmpty) {
              material.Navigator.pop(context, {
                'name': _nameController.text.trim(),
                'description': _descriptionController.text.trim(),
                'category': _selectedCategory,
                'isPrivate': _isPrivate.toString(),
              });
            }
          },
          style: material.Theme.of(context).elevatedButtonTheme.style,
          child: const material.Text('Create'),
        ),
      ],
    );
  }
}

class CommunityDetailsScreen extends material.StatefulWidget {
  final Map<String, dynamic> community;

  const CommunityDetailsScreen({super.key, required this.community});

  @override
  material.State<CommunityDetailsScreen> createState() => _CommunityDetailsScreenState();
}

class _CommunityDetailsScreenState extends material.State<CommunityDetailsScreen> with material.TickerProviderStateMixin {
  late material.TabController _tabController;
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isAdmin = false;
  List<Map<String, dynamic>> _joinRequests = [];

  @override
  void initState() {
    super.initState();
    _tabController = material.TabController(length: 6, vsync: this);
    _checkAdminStatus();
    _loadJoinRequests();
  }

  Future<void> _checkAdminStatus() async {
    try {
      final response = await _supabase
          .from('community_members')
          .select('role')
          .eq('community_id', widget.community['id'])
          .eq('user_id', _supabase.auth.currentUser!.id)
          .single();

      setState(() {
        _isAdmin = response['role'] == 'admin' || widget.community['creator_id'] == _supabase.auth.currentUser!.id;
      });
    } catch (e) {
      // User is not a member
    }
  }

  Future<void> _loadJoinRequests() async {
    if (!_isAdmin) return;

    try {
      final response = await _supabase
          .from('community_join_requests')
          .select('*, user_profiles(username, full_name)')
          .eq('community_id', widget.community['id'])
          .eq('status', 'pending');

      setState(() {
        _joinRequests = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      // Handle error
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    return material.Scaffold(
      backgroundColor: material.Theme.of(context).scaffoldBackgroundColor,
      appBar: material.AppBar(
        title: material.Text(widget.community['name'] ?? 'Community', style: material.Theme.of(context).appBarTheme.titleTextStyle),
        backgroundColor: material.Theme.of(context).appBarTheme.backgroundColor,
        actions: [
          if (_isAdmin) ...[
            material.IconButton(
              icon: const material.Icon(material.Icons.admin_panel_settings),
              onPressed: () => _showAdminPanel(),
            ),
          ],
        ],
        bottom: material.TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: material.Theme.of(context).textTheme.titleLarge?.color,
          unselectedLabelColor: material.Theme.of(context).textTheme.labelMedium?.color,
          tabs: const [
            material.Tab(icon: material.Icon(material.Icons.chat), text: 'Chat'),
            material.Tab(icon: material.Icon(material.Icons.article), text: 'Posts'),
            material.Tab(icon: material.Icon(material.Icons.event), text: 'Events'),
            material.Tab(icon: material.Icon(material.Icons.folder), text: 'Files'),
            material.Tab(icon: material.Icon(material.Icons.people), text: 'Members'),
            material.Tab(icon: material.Icon(material.Icons.info), text: 'About'),
          ],
        ),
      ),
      body: material.TabBarView(
        controller: _tabController,
        children: [
          _CommunityChat(community: widget.community),
          _CommunityPosts(community: widget.community),
          _CommunityEvents(community: widget.community),
          _CommunityFiles(community: widget.community),
          _CommunityMembers(community: widget.community),
          _CommunityAbout(community: widget.community),
        ],
      ),
    );
  }

  void _showAdminPanel() {
    material.showModalBottomSheet(
      context: context,
      backgroundColor: material.Theme.of(context).colorScheme.surface,
      builder: (context) => _AdminPanel(
        community: widget.community,
        joinRequests: _joinRequests,
        onRequestsUpdated: _loadJoinRequests,
      ),
    );
  }
}

class _CommunityChat extends material.StatefulWidget {
  final Map<String, dynamic> community;

  const _CommunityChat({required this.community});

  @override
  material.State<_CommunityChat> createState() => _CommunityChatState();
}

class _CommunityChatState extends material.State<_CommunityChat> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final material.TextEditingController _messageController = material.TextEditingController();
  final material.ScrollController _scrollController = material.ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribeToMessages();
  }

  Future<void> _loadMessages() async {
    try {
      final response = await _supabase
          .from('community_messages')
          .select('*, user_profiles(username, full_name, avatar_url)')
          .eq('community_id', widget.community['id'])
          .order('created_at', ascending: true);

      setState(() {
        _messages = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });

      _scrollToBottom();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _subscribeToMessages() {
    _supabase
        .channel('community_messages_${widget.community['id']}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'community_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'community_id',
            value: widget.community['id'],
          ),
          callback: (payload) {
            _loadMessages();
          },
        )
        .subscribe();
  }
 void _scrollToBottom() {
    material.WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300), // Changed from material.Duration to Duration
          curve: material.Curves.easeOut,
        );
      }
    });
  }
  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    try {
      await _supabase.from('community_messages').insert({
        'community_id': widget.community['id'],
        'user_id': _supabase.auth.currentUser!.id,
        'message': _messageController.text.trim(),
      });

      _messageController.clear();
    } catch (e) {
      material.ScaffoldMessenger.of(context).showSnackBar(
        material.SnackBar(
          content: material.Text('Error sending message: $e'),
          backgroundColor: material.Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    if (_isLoading) {
      return const material.Center(child: material.CircularProgressIndicator());
    }

    return material.Column(
      children: [
        material.Expanded(
          child: material.ListView.builder(
            controller: _scrollController,
            padding: const material.EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final message = _messages[index];
              final isCurrentUser = message['user_id'] == _supabase.auth.currentUser!.id;
              final profile = message['user_profiles'];

              return material.Padding(
                padding: const material.EdgeInsets.symmetric(vertical: 4),
                child: material.Row(
                  mainAxisAlignment: isCurrentUser ? material.MainAxisAlignment.end : material.MainAxisAlignment.start,
                  children: [
                    if (!isCurrentUser) ...[
                      material.CircleAvatar(
                        radius: 16,
                        backgroundImage: profile?['avatar_url'] != null ? material.NetworkImage(profile['avatar_url']) : null,
                        child: profile?['avatar_url'] == null ? material.Text(profile?['username']?[0]?.toUpperCase() ?? 'U') : null,
                      ),
                      const material.SizedBox(width: 8),
                    ],
                    material.Flexible(
                      child: material.Container(
                        padding: const material.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: material.BoxDecoration(
                          color: isCurrentUser ? material.Theme.of(context).colorScheme.primary : material.Theme.of(context).colorScheme.surface,
                          borderRadius: material.BorderRadius.circular(16),
                        ),
                        child: material.Column(
                          crossAxisAlignment: material.CrossAxisAlignment.start,
                          children: [
                            if (!isCurrentUser)
                              material.Text(
                                profile?['username'] ?? 'Unknown',
                                style: material.Theme.of(context).textTheme.labelMedium,
                              ),
                            material.Text(
                              message['message'] ?? '',
                              style: material.TextStyle(
                                color: isCurrentUser ? material.Colors.white : material.Theme.of(context).textTheme.bodyMedium?.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        material.Container(
          padding: const material.EdgeInsets.all(16),
          decoration: material.BoxDecoration(
            color: material.Theme.of(context).colorScheme.surface,
            border: material.Border(top: material.BorderSide(color: material.Theme.of(context).dividerColor)),
          ),
          child: material.Row(
            children: [
              material.Expanded(
                child: material.TextField(
                  controller: _messageController,
                  decoration: material.InputDecoration(
                    hintText: 'Type a message...',
                    border: material.Theme.of(context).inputDecorationTheme.border ?? const material.OutlineInputBorder(),
                    labelStyle: material.Theme.of(context).inputDecorationTheme.labelStyle,
                    filled: material.Theme.of(context).inputDecorationTheme.filled,
                    fillColor: material.Theme.of(context).inputDecorationTheme.fillColor,
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const material.SizedBox(width: 8),
              material.FloatingActionButton(
                mini: true,
                onPressed: _sendMessage,
                backgroundColor: material.Theme.of(context).colorScheme.primary,
                child: const material.Icon(material.Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class _CommunityPosts extends material.StatefulWidget {
  final Map<String, dynamic> community;

  const _CommunityPosts({required this.community});

  @override
  material.State<_CommunityPosts> createState() => _CommunityPostsState();
}

class _CommunityPostsState extends material.State<_CommunityPosts> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    try {
      final response = await _supabase
          .from('community_posts')
          .select('*, user_profiles(username, full_name, avatar_url)')
          .eq('community_id', widget.community['id'])
          .order('created_at', ascending: false);

      setState(() {
        _posts = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createPost() async {
    final result = await material.showDialog<Map<String, String>>(
      context: context,
      builder: (context) => const _CreatePostDialog(),
    );

    if (result != null) {
      try {
        await _supabase.from('community_posts').insert({
          'community_id': widget.community['id'],
          'user_id': _supabase.auth.currentUser!.id,
          'title': result['title'],
          'content': result['content'],
        });

        _loadPosts();
        material.ScaffoldMessenger.of(context).showSnackBar(
          material.SnackBar(
            content: const material.Text('Post created successfully!'),
            backgroundColor: material.Theme.of(context).snackBarTheme.backgroundColor,
          ),
        );
      } catch (e) {
        material.ScaffoldMessenger.of(context).showSnackBar(
          material.SnackBar(
            content: material.Text('Error creating post: $e'),
            backgroundColor: material.Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    if (_isLoading) {
      return const material.Center(child: material.CircularProgressIndicator());
    }

    return material.Column(
      children: [
        material.Padding(
          padding: const material.EdgeInsets.all(16),
          child: material.ElevatedButton.icon(
            onPressed: _createPost,
            icon: const material.Icon(material.Icons.add),
            label: const material.Text('Create Post'),
            style: material.Theme.of(context).elevatedButtonTheme.style,
          ),
        ),
        material.Expanded(
          child: _posts.isEmpty
              ? material.Center(
                  child: material.Text(
                    'No posts yet. Be the first to post!',
                    style: material.Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : material.ListView.builder(
                  padding: const material.EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _posts.length,
                  itemBuilder: (context, index) {
                    final post = _posts[index];
                    final profile = post['user_profiles'];

                    return material.Card(
                      margin: const material.EdgeInsets.only(bottom: 16),
                      color: material.Theme.of(context).colorScheme.surface,
                      child: material.Padding(
                        padding: const material.EdgeInsets.all(16),
                        child: material.Column(
                          crossAxisAlignment: material.CrossAxisAlignment.start,
                          children: [
                            material.Row(
                              children: [
                                material.CircleAvatar(
                                  radius: 20,
                                  backgroundImage: profile?['avatar_url'] != null ? material.NetworkImage(profile['avatar_url']) : null,
                                  child: profile?['avatar_url'] == null ? material.Text(profile?['username']?[0]?.toUpperCase() ?? 'U') : null,
                                ),
                                const material.SizedBox(width: 12),
                                material.Expanded(
                                  child: material.Column(
                                    crossAxisAlignment: material.CrossAxisAlignment.start,
                                    children: [
                                      material.Text(
                                        profile?['full_name'] ?? profile?['username'] ?? 'Unknown',
                                        style: material.Theme.of(context).textTheme.titleLarge,
                                      ),
                                      material.Text(
                                        _formatDateTime(post['created_at']),
                                        style: material.Theme.of(context).textTheme.labelMedium,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const material.SizedBox(height: 12),
                            material.Text(
                              post['title'] ?? '',
                              style: material.Theme.of(context).textTheme.titleLarge,
                            ),
                            const material.SizedBox(height: 8),
                            material.Text(
                              post['content'] ?? '',
                              style: material.Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _formatDateTime(String? dateTime) {
    if (dateTime == null) return '';
    try {
      final date = DateTime.parse(dateTime);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return '';
    }
  }
}

class _CreatePostDialog extends material.StatefulWidget {
  const _CreatePostDialog();

  @override
  material.State<_CreatePostDialog> createState() => _CreatePostDialogState();
}

class _CreatePostDialogState extends material.State<_CreatePostDialog> {
  final _titleController = material.TextEditingController();
  final _contentController = material.TextEditingController();

  @override
  material.Widget build(material.BuildContext context) {
    return material.AlertDialog(
      backgroundColor: material.Theme.of(context).colorScheme.surface,
      title: material.Text('Create Post', style: material.Theme.of(context).textTheme.titleLarge),
      content: material.SingleChildScrollView(
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            material.TextField(
              controller: _titleController,
              decoration: material.InputDecoration(
                labelText: 'Post Title',
                border: material.Theme.of(context).inputDecorationTheme.border ?? const material.OutlineInputBorder(),
                labelStyle: material.Theme.of(context).inputDecorationTheme.labelStyle,
                filled: material.Theme.of(context).inputDecorationTheme.filled,
                fillColor: material.Theme.of(context).inputDecorationTheme.fillColor,
              ),
            ),
            const material.SizedBox(height: 16),
            material.TextField(
              controller: _contentController,
              decoration: material.InputDecoration(
                labelText: 'Content',
                border: material.Theme.of(context).inputDecorationTheme.border ?? const material.OutlineInputBorder(),
                labelStyle: material.Theme.of(context).inputDecorationTheme.labelStyle,
                filled: material.Theme.of(context).inputDecorationTheme.filled,
                fillColor: material.Theme.of(context).inputDecorationTheme.fillColor,
              ),
              maxLines: 5,
            ),
          ],
        ),
      ),
      actions: [
        material.TextButton(
          onPressed: () => material.Navigator.pop(context),
          child: material.Text('Cancel', style: material.Theme.of(context).textTheme.labelLarge),
        ),
        material.ElevatedButton(
          onPressed: () {
            if (_titleController.text.trim().isNotEmpty && _contentController.text.trim().isNotEmpty) {
              material.Navigator.pop(context, {
                'title': _titleController.text.trim(),
                'content': _contentController.text.trim(),
              });
            }
          },
          style: material.Theme.of(context).elevatedButtonTheme.style,
          child: const material.Text('Post'),
        ),
      ],
    );
  }
}

class _CommunityEvents extends material.StatefulWidget {
  final Map<String, dynamic> community;

  const _CommunityEvents({required this.community});

  @override
  material.State<_CommunityEvents> createState() => _CommunityEventsState();
}

class _CommunityEventsState extends material.State<_CommunityEvents> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _events = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    try {
      final response = await _supabase
          .from('community_events')
          .select('*, user_profiles(username, full_name)')
          .eq('community_id', widget.community['id'])
          .order('event_date', ascending: true);

      setState(() {
        _events = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createEvent() async {
    final result = await material.showDialog<Map<String, String>>(
      context: context,
      builder: (context) => const _CreateEventDialog(),
    );

    if (result != null) {
      try {
        await _supabase.from('community_events').insert({
          'community_id': widget.community['id'],
          'creator_id': _supabase.auth.currentUser!.id,
          'title': result['title'],
          'description': result['description'],
          'event_date': result['date'],
          'location': result['location'],
        });

        _loadEvents();
        material.ScaffoldMessenger.of(context).showSnackBar(
          material.SnackBar(
            content: const material.Text('Event created successfully!'),
            backgroundColor: material.Theme.of(context).snackBarTheme.backgroundColor,
          ),
        );
      } catch (e) {
        material.ScaffoldMessenger.of(context).showSnackBar(
          material.SnackBar(
            content: material.Text('Error creating event: $e'),
            backgroundColor: material.Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    if (_isLoading) {
      return const material.Center(child: material.CircularProgressIndicator());
    }

    return material.Column(
      children: [
        material.Padding(
          padding: const material.EdgeInsets.all(16),
          child: material.ElevatedButton.icon(
            onPressed: _createEvent,
            icon: const material.Icon(material.Icons.event),
            label: const material.Text('Create Event'),
            style: material.Theme.of(context).elevatedButtonTheme.style,
          ),
        ),
        material.Expanded(
          child: _events.isEmpty
              ? material.Center(
                  child: material.Text(
                    'No events scheduled yet.',
                    style: material.Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : material.ListView.builder(
                  padding: const material.EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _events.length,
                  itemBuilder: (context, index) {
                    final event = _events[index];
                    final eventDate = DateTime.tryParse(event['event_date'] ?? '');
                    final isUpcoming = eventDate?.isAfter(DateTime.now()) ?? false;

                    return material.Card(
                      margin: const material.EdgeInsets.only(bottom: 16),
                      color: material.Theme.of(context).colorScheme.surface,
                      child: material.Padding(
                        padding: const material.EdgeInsets.all(16),
                        child: material.Column(
                          crossAxisAlignment: material.CrossAxisAlignment.start,
                          children: [
                            material.Row(
                              children: [
                                material.Icon(
                                  material.Icons.event,
                                  color: isUpcoming ? material.Colors.green : material.Theme.of(context).iconTheme.color,
                                ),
                                const material.SizedBox(width: 8),
                                material.Expanded(
                                  child: material.Text(
                                    event['title'] ?? '',
                                    style: material.Theme.of(context).textTheme.titleLarge,
                                  ),
                                ),
                                if (isUpcoming)
                                  material.Container(
                                    padding: const material.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: material.BoxDecoration(
                                      color: material.Colors.green,
                                      borderRadius: material.BorderRadius.circular(12),
                                    ),
                                    child: const material.Text(
                                      'Upcoming',
                                      style: material.TextStyle(
                                        color: material.Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const material.SizedBox(height: 8),
                            material.Text(
                              event['description'] ?? '',
                              style: material.Theme.of(context).textTheme.bodyMedium,
                            ),
                            const material.SizedBox(height: 12),
                            material.Row(
                              children: [
                                material.Icon(material.Icons.schedule, size: 16, color: material.Theme.of(context).iconTheme.color),
                                const material.SizedBox(width: 4),
                                material.Text(
                                  _formatEventDate(event['event_date']),
                                  style: material.Theme.of(context).textTheme.labelMedium,
                                ),
                              ],
                            ),
                            if (event['location'] != null) ...[
                              const material.SizedBox(height: 4),
                              material.Row(
                                children: [
                                  material.Icon(material.Icons.location_on, size: 16, color: material.Theme.of(context).iconTheme.color),
                                  const material.SizedBox(width: 4),
                                  material.Expanded(
                                    child: material.Text(
                                      event['location'],
                                      style: material.Theme.of(context).textTheme.labelMedium,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _formatEventDate(String? dateTime) {
    if (dateTime == null) return '';
    try {
      final date = DateTime.parse(dateTime);
      return '${date.day}/${date.month}/${date.year} at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateTime;
    }
  }
}

class _CreateEventDialog extends material.StatefulWidget {
  const _CreateEventDialog();

  @override
  material.State<_CreateEventDialog> createState() => _CreateEventDialogState();
}

class _CreateEventDialogState extends material.State<_CreateEventDialog> {
  final _titleController = material.TextEditingController();
  final _descriptionController = material.TextEditingController();
  final _locationController = material.TextEditingController();
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1)); // Remove material. prefix

 @override
  material.Widget build(material.BuildContext context) {
    return material.AlertDialog(
      backgroundColor: material.Theme.of(context).colorScheme.surface,
      title: material.Text('Create Event', style: material.Theme.of(context).textTheme.titleLarge),
      content: material.SingleChildScrollView(
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            material.TextField(
              controller: _titleController,
              decoration: material.InputDecoration(
                labelText: 'Event Title',
                border: material.Theme.of(context).inputDecorationTheme.border ?? const material.OutlineInputBorder(),
                labelStyle: material.Theme.of(context).inputDecorationTheme.labelStyle,
                filled: material.Theme.of(context).inputDecorationTheme.filled,
                fillColor: material.Theme.of(context).inputDecorationTheme.fillColor,
              ),
            ),
            const material.SizedBox(height: 16),
            material.TextField(
              controller: _descriptionController,
              decoration: material.InputDecoration(
                labelText: 'Description',
                border: material.Theme.of(context).inputDecorationTheme.border ?? const material.OutlineInputBorder(),
                labelStyle: material.Theme.of(context).inputDecorationTheme.labelStyle,
                filled: material.Theme.of(context).inputDecorationTheme.filled,
                fillColor: material.Theme.of(context).inputDecorationTheme.fillColor,
              ),
              maxLines: 3,
            ),
            const material.SizedBox(height: 16),
            material.TextField(
              controller: _locationController,
              decoration: material.InputDecoration(
                labelText: 'Location (optional)',
                border: material.Theme.of(context).inputDecorationTheme.border ?? const material.OutlineInputBorder(),
                labelStyle: material.Theme.of(context).inputDecorationTheme.labelStyle,
                filled: material.Theme.of(context).inputDecorationTheme.filled,
                fillColor: material.Theme.of(context).inputDecorationTheme.fillColor,
              ),
            ),
            const material.SizedBox(height: 16),
            material.ListTile(
              title: material.Text('Event Date & Time', style: material.Theme.of(context).textTheme.titleLarge),
              subtitle: material.Text(
                '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year} at ${_selectedDate.hour.toString().padLeft(2, '0')}:${_selectedDate.minute.toString().padLeft(2, '0')}',
                style: material.Theme.of(context).textTheme.bodyMedium,
              ),
              trailing: const material.Icon(material.Icons.calendar_today),
              onTap: () async {
                final date = await material.showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)), // Fixed: removed material. prefix
                );

                if (date != null) {
                  final time = await material.showTimePicker(
                    context: context,
                    initialTime: material.TimeOfDay.fromDateTime(_selectedDate),
                  );

                  if (time != null) {
                    setState(() {
                      _selectedDate = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                    });
                  }
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        material.TextButton(
          onPressed: () => material.Navigator.pop(context),
          child: material.Text('Cancel', style: material.Theme.of(context).textTheme.labelLarge),
        ),
        material.ElevatedButton(
          onPressed: () {
            if (_titleController.text.trim().isNotEmpty) {
              material.Navigator.pop(context, {
                'title': _titleController.text.trim(),
                'description': _descriptionController.text.trim(),
                'location': _locationController.text.trim(),
                'date': _selectedDate.toIso8601String(),
              });
            }
          },
          style: material.Theme.of(context).elevatedButtonTheme.style,
          child: const material.Text('Create'),
        ),
      ],
    );
  }
}
class _CommunityFiles extends material.StatefulWidget {
  final Map<String, dynamic> community;

  const _CommunityFiles({required this.community});

  @override
  material.State<_CommunityFiles> createState() => _CommunityFilesState();
}

class _CommunityFilesState extends material.State<_CommunityFiles> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _files = [];
  bool _isLoading = true;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    try {
      final response = await _supabase
          .from('community_files')
          .select('*, user_profiles(username, full_name)')
          .eq('community_id', widget.community['id'])
          .order('created_at', ascending: false);

      setState(() {
        _files = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.any,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() => _isUploading = true);

        final file = result.files.first;
        final fileName = path.basename(file.name); // Use path.basename for safe file name handling
        final storagePath = '${widget.community['id']}/${DateTime.now().millisecondsSinceEpoch}_$fileName';

        final fileBytes = file.bytes!;
        await _supabase.storage.from('community_files').uploadBinary(storagePath, fileBytes);

        final publicUrl = _supabase.storage.from('community_files').getPublicUrl(storagePath);

        await _supabase.from('community_files').insert({
          'community_id': widget.community['id'],
          'uploader_id': _supabase.auth.currentUser!.id,
          'file_name': file.name,
          'file_size': file.size,
          'file_type': file.extension,
          'file_url': publicUrl,
        });

        _loadFiles();
        material.ScaffoldMessenger.of(context).showSnackBar(
          material.SnackBar(
            content: const material.Text('File uploaded successfully!'),
            backgroundColor: material.Theme.of(context).snackBarTheme.backgroundColor,
          ),
        );
      }
    } catch (e) {
      material.ScaffoldMessenger.of(context).showSnackBar(
        material.SnackBar(
          content: material.Text('Error uploading file: $e'),
          backgroundColor: material.Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      setState(() => _isUploading = false);
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    if (_isLoading) {
      return const material.Center(child: material.CircularProgressIndicator());
    }

    return material.Column(
      children: [
        material.Padding(
          padding: const material.EdgeInsets.all(16),
          child: material.ElevatedButton.icon(
            onPressed: _isUploading ? null : _uploadFile,
            icon: _isUploading
                ? const material.SizedBox(
                    width: 16,
                    height: 16,
                    child: material.CircularProgressIndicator(strokeWidth: 2),
                  )
                : const material.Icon(material.Icons.upload_file),
            label: material.Text(_isUploading ? 'Uploading...' : 'Upload File'),
            style: material.Theme.of(context).elevatedButtonTheme.style,
          ),
        ),
        material.Expanded(
          child: _files.isEmpty
              ? material.Center(
                  child: material.Text(
                    'No files uploaded yet.',
                    style: material.Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : material.ListView.builder(
                  padding: const material.EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final file = _files[index];
                    final profile = file['user_profiles'];

                    return material.Card(
                      margin: const material.EdgeInsets.only(bottom: 12),
                      color: material.Theme.of(context).colorScheme.surface,
                      child: material.ListTile(
                        leading: material.CircleAvatar(
                          backgroundColor: _getFileTypeColor(file['file_type']),
                          child: material.Icon(
                            _getFileTypeIcon(file['file_type']),
                            color: material.Colors.white,
                          ),
                        ),
                        title: material.Text(
                          file['file_name'] ?? 'Unknown File',
                          style: material.Theme.of(context).textTheme.titleLarge,
                        ),
                        subtitle: material.Column(
                          crossAxisAlignment: material.CrossAxisAlignment.start,
                          children: [
                            material.Text('Uploaded by ${profile?['username'] ?? 'Unknown'}'),
                            material.Text(
                              '${_formatFileSize(file['file_size'])} • ${_formatDateTime(file['created_at'])}',
                              style: material.Theme.of(context).textTheme.labelMedium,
                            ),
                          ],
                        ),
                        trailing: material.IconButton(
                          icon: const material.Icon(material.Icons.download),
                          onPressed: () => _downloadFile(file),
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  material.Color _getFileTypeColor(String? fileType) {
    switch (fileType?.toLowerCase()) {
      case 'pdf':
        return material.Colors.red;
      case 'doc':
      case 'docx':
        return material.Colors.blue;
      case 'xls':
      case 'xlsx':
        return material.Colors.green;
      case 'ppt':
      case 'pptx':
        return material.Colors.orange;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return material.Colors.purple;
      case 'mp4':
      case 'avi':
      case 'mov':
        return material.Colors.indigo;
      case 'mp3':
      case 'wav':
        return material.Colors.teal;
      default:
        return material.Colors.grey;
    }
  }

  material.IconData _getFileTypeIcon(String? fileType) {
    switch (fileType?.toLowerCase()) {
      case 'pdf':
        return material.Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return material.Icons.description;
      case 'xls':
      case 'xlsx':
        return material.Icons.table_rows;
      case 'ppt':
      case 'pptx':
        return material.Icons.slideshow;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return material.Icons.image;
      case 'mp4':
      case 'avi':
      case 'mov':
        return material.Icons.video_file;
      case 'mp3':
      case 'wav':
        return material.Icons.audio_file;
      case 'zip':
      case 'rar':
        return material.Icons.archive;
      default:
        return material.Icons.insert_drive_file;
    }
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDateTime(String? dateTime) {
    if (dateTime == null) return '';
    try {
      final date = DateTime.parse(dateTime);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return '';
    }
  }

  void _downloadFile(Map<String, dynamic> file) {
    material.ScaffoldMessenger.of(context).showSnackBar(
      material.SnackBar(
        content: material.Text('Downloading ${file['file_name']}...'),
        backgroundColor: material.Theme.of(context).snackBarTheme.backgroundColor,
      ),
    );
  }
}

class _CommunityMembers extends material.StatefulWidget {
  final Map<String, dynamic> community;

  const _CommunityMembers({required this.community});

  @override
  material.State<_CommunityMembers> createState() => _CommunityMembersState();
}

class _CommunityMembersState extends material.State<_CommunityMembers> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _members = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    try {
      final response = await _supabase
          .from('community_members')
          .select('*, user_profiles(username, full_name, avatar_url)')
          .eq('community_id', widget.community['id'])
          .order('joined_at', ascending: false);

      setState(() {
        _members = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    if (_isLoading) {
      return const material.Center(child: material.CircularProgressIndicator());
    }

    return material.ListView.builder(
      padding: const material.EdgeInsets.all(16),
      itemCount: _members.length,
      itemBuilder: (context, index) {
        final member = _members[index];
        final profile = member['user_profiles'];
        final isAdmin = member['role'] == 'admin';
        final isCreator = widget.community['creator_id'] == member['user_id'];

        return material.Card(
          margin: const material.EdgeInsets.only(bottom: 12),
          color: material.Theme.of(context).colorScheme.surface,
          child: material.ListTile(
            leading: material.CircleAvatar(
              backgroundImage: profile?['avatar_url'] != null ? material.NetworkImage(profile['avatar_url']) : null,
              child: profile?['avatar_url'] == null ? material.Text(profile?['username']?[0]?.toUpperCase() ?? 'U') : null,
            ),
            title: material.Text(
              profile?['full_name'] ?? profile?['username'] ?? 'Unknown',
              style: material.Theme.of(context).textTheme.titleLarge,
            ),
            subtitle: material.Text(
              'Joined ${_formatDateTime(member['joined_at'])}',
              style: material.Theme.of(context).textTheme.labelMedium,
            ),
            trailing: material.Row(
              mainAxisSize: material.MainAxisSize.min,
              children: [
                if (isCreator)
                  material.Container(
                    padding: const material.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: material.BoxDecoration(
                      color: material.Colors.yellow[700],
                      borderRadius: material.BorderRadius.circular(12),
                    ),
                    child: const material.Text(
                      'Creator',
                      style: material.TextStyle(
                        color: material.Colors.white,
                        fontSize: 12,
                        fontWeight: material.FontWeight.bold,
                      ),
                    ),
                  )
                else if (isAdmin)
                  material.Container(
                    padding: const material.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: material.BoxDecoration(
                      color: material.Colors.blue,
                      borderRadius: material.BorderRadius.circular(12),
                    ),
                    child: const material.Text(
                      'Admin',
                      style: material.TextStyle(
                        color: material.Colors.white,
                        fontSize: 12,
                        fontWeight: material.FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDateTime(String? dateTime) {
    if (dateTime == null) return '';
    try {
      final date = DateTime.parse(dateTime);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return '';
    }
  }
}

class _CommunityAbout extends material.StatelessWidget {
  final Map<String, dynamic> community;

  const _CommunityAbout({required this.community});

  @override
  material.Widget build(material.BuildContext context) {
    return material.Padding(
      padding: const material.EdgeInsets.all(16),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        children: [
          material.Card(
            color: material.Theme.of(context).colorScheme.surface,
            child: material.Padding(
              padding: const material.EdgeInsets.all(16),
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.start,
                children: [
                  material.Text(
                    'About ${community['name']}',
                    style: material.Theme.of(context).textTheme.titleLarge,
                  ),
                  const material.SizedBox(height: 12),
                  material.Text(
                    community['description'] ?? 'No description available.',
                    style: material.Theme.of(context).textTheme.bodyMedium,
                  ),
                  const material.SizedBox(height: 16),
                  _buildInfoRow(material.Icons.category, 'Category', community['category'] ?? 'General'),
                  const material.SizedBox(height: 8),
                  _buildInfoRow(
                    community['is_private'] == true ? material.Icons.lock : material.Icons.public,
                    'Type',
                    community['is_private'] == true ? 'Private' : 'Public',
                  ),
                  const material.SizedBox(height: 8),
                  _buildInfoRow(
                    material.Icons.calendar_today,
                    'Created',
                    _formatDateTime(community['created_at']),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  material.Widget _buildInfoRow(material.IconData icon, String label, String value) {
    return material.Row(
      children: [
        material.Icon(icon, size: 20, color: material.Theme.of(path_lib.context as material.BuildContext).iconTheme.color),
        const material.SizedBox(width: 12),
        material.Text(
          '$label: ',
          style: material.Theme.of(path_lib.context as material.BuildContext).textTheme.titleLarge,
        ),
        material.Expanded(child: material.Text(value, style: material.Theme.of(path_lib.context as material.BuildContext).textTheme.bodyMedium)),
      ],
    );
  }

  String _formatDateTime(String? dateTime) {
    if (dateTime == null) return '';
    try {
      final date = DateTime.parse(dateTime);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return '';
    }
  }
}

class _AdminPanel extends material.StatefulWidget {
  final Map<String, dynamic> community;
  final List<Map<String, dynamic>> joinRequests;
  final material.VoidCallback onRequestsUpdated;

  const _AdminPanel({
    required this.community,
    required this.joinRequests,
    required this.onRequestsUpdated,
  });

  @override
  material.State<_AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends material.State<_AdminPanel> {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> _approveJoinRequest(Map<String, dynamic> request) async {
    try {
      await _supabase.from('community_join_requests').update({
        'status': 'approved',
      }).eq('id', request['id']);

      await _supabase.from('community_members').insert({
        'community_id': widget.community['id'],
        'user_id': request['user_id'],
        'role': 'member',
      });

      widget.onRequestsUpdated();
      material.ScaffoldMessenger.of(context).showSnackBar(
        material.SnackBar(
          content: const material.Text('Join request approved!'),
          backgroundColor: material.Theme.of(context).snackBarTheme.backgroundColor,
        ),
      );
    } catch (e) {
      material.ScaffoldMessenger.of(context).showSnackBar(
        material.SnackBar(
          content: material.Text('Error approving request: $e'),
          backgroundColor: material.Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _rejectJoinRequest(Map<String, dynamic> request) async {
    try {
      await _supabase.from('community_join_requests').update({
        'status': 'rejected',
      }).eq('id', request['id']);

      widget.onRequestsUpdated();
      material.ScaffoldMessenger.of(context).showSnackBar(
        material.SnackBar(
          content: const material.Text('Join request rejected.'),
          backgroundColor: material.Theme.of(context).snackBarTheme.backgroundColor,
        ),
      );
    } catch (e) {
      material.ScaffoldMessenger.of(context).showSnackBar(
        material.SnackBar(
          content: material.Text('Error rejecting request: $e'),
          backgroundColor: material.Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    return material.Container(
      padding: const material.EdgeInsets.all(16),
      color: material.Theme.of(context).colorScheme.surface,
      child: material.Column(
        mainAxisSize: material.MainAxisSize.min,
        crossAxisAlignment: material.CrossAxisAlignment.start,
        children: [
          material.Text(
            'Admin Panel',
            style: material.Theme.of(context).textTheme.titleLarge,
          ),
          const material.SizedBox(height: 16),
          if (widget.joinRequests.isNotEmpty) ...[
            material.Text(
              'Join Requests (${widget.joinRequests.length})',
              style: material.Theme.of(context).textTheme.titleLarge,
            ),
            const material.SizedBox(height: 12),
            ...widget.joinRequests.map((request) => _buildJoinRequestItem(request)),
          ] else ...[
            material.Text(
              'No pending join requests',
              style: material.Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }

  material.Widget _buildJoinRequestItem(Map<String, dynamic> request) {
    final profile = request['user_profiles'];

    return material.Card(
      margin: const material.EdgeInsets.only(bottom: 8),
      color: material.Theme.of(context).colorScheme.surface,
      child: material.ListTile(
        title: material.Text(
          profile?['full_name'] ?? profile?['username'] ?? 'Unknown',
          style: material.Theme.of(context).textTheme.titleLarge,
        ),
        subtitle: request['message']?.isNotEmpty == true
            ? material.Text(
                request['message'],
                style: material.Theme.of(context).textTheme.bodyMedium,
              )
            : material.Text(
                'No message',
                style: material.Theme.of(context).textTheme.bodyMedium,
              ),
        trailing: material.Row(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            material.IconButton(
              icon: const material.Icon(material.Icons.check, color: material.Colors.green),
              onPressed: () => _approveJoinRequest(request),
            ),
            material.IconButton(
              icon: const material.Icon(material.Icons.close, color: material.Colors.red),
              onPressed: () => _rejectJoinRequest(request),
            ),
          ],
        ),
      ),
    );
  }
}