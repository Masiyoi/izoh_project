import 'package:flutter/material.dart';
import 'package:unic_connect/utils/supabase_client.dart';
import 'package:uuid/uuid.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final supabase = SupabaseClientUtil.client;
  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _searchResults = [];
  Map<String, dynamic>? _currentUserProfile;
  bool _isLoading = true;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _setupRealtime();
    _setupSearchListener();
    _loadCurrentUserProfile(); 
  }

  @override
  void dispose() {
    _searchController.dispose();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  void _setupSearchListener() {
    _searchController.addListener(() {
      if (_searchController.text.isNotEmpty) {
        _searchUsers(_searchController.text);
      } else {
        setState(() {
          _searchResults.clear();
        });
      }
    });
  }

  Future<void> _setupRealtime() async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    _realtimeChannel = supabase.channel('messages-$currentUserId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (payload) {
          _loadConversations();
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'conversations',
        callback: (payload) {
          _loadConversations();
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'message_read_status',
        callback: (payload) {
          _loadConversations();
        },
      )
      ..subscribe();
  }

  Future<void> _loadCurrentUserProfile() async {
    try {
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) return;
      
      final response = await supabase
          .from('profiles')
          .select('id, username, full_name, profile_image_url, avatar_url')
          .eq('id', currentUserId)
          .single();
      
      setState(() {
        _currentUserProfile = response;
      });
    } catch (e) {
      // Handle error if needed
    }
  }

  Future<void> _loadConversations() async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      // Get all conversations and their participants
      final response = await supabase
          .from('conversations')
          .select('''
            id,
            created_at,
            updated_at,
            conversation_participants(
              user_id,
              profiles(
                id,
                username,
                full_name,
                profile_image_url,
                avatar_url
              )
            ),
            last_message:messages(
              id,
              content,
              created_at,
              sender_id,
              sender:profiles(username)
            )
          ''')
          .order('updated_at', ascending: false);

      if (mounted) {
        List<Map<String, dynamic>> processedConversations = [];

        for (var conv in response) {
          // Only include conversations where current user is a participant
          final participants = conv['conversation_participants'] as List<dynamic>;
          final isParticipant = participants.any((p) => p['user_id'] == currentUserId);
          final hasOtherParticipant = participants.any((p) => p['user_id'] != currentUserId);
          
          if (!isParticipant || !hasOtherParticipant) continue;

          // Find the other participant (not the current user)
          final otherParticipant = participants.firstWhere(
            (p) => p['user_id'] != currentUserId,
          );
          
          final lastMessages = conv['last_message'] as List<dynamic>? ?? [];
          final lastMessage = lastMessages.isNotEmpty 
              ? lastMessages.reduce((a, b) => 
                  DateTime.parse(a['created_at']).isAfter(DateTime.parse(b['created_at'])) ? a : b)
              : null;

          // Get unread count for this conversation
          final unreadCount = await _getUnreadCount(conv['id'], currentUserId);

          processedConversations.add({
            ...conv,
            'other_participant': otherParticipant,
            'last_message': lastMessage,
            'unread_count': unreadCount,
          });
        }

        setState(() {
          _conversations = processedConversations;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Error loading conversations: $e', isError: true);
      }
    }
  }

  Future<int> _getUnreadCount(String conversationId, String currentUserId) async {
    try {
      // Get all messages in this conversation that are not sent by current user
      final messages = await supabase
          .from('messages')
          .select('id')
          .eq('conversation_id', conversationId)
          .neq('sender_id', currentUserId);

      if (messages.isEmpty) return 0;

      // Get read status for these messages
      final readMessages = await supabase
          .from('message_read_status')
          .select('message_id')
          .eq('user_id', currentUserId)
          .inFilter('message_id', messages.map((m) => m['id']).toList());

      // Calculate unread count
      return messages.length - readMessages.length;
    } catch (e) {
      return 0;
    }
  }

  // Get total unread messages count across all conversations
  int get _totalUnreadCount {
    return _conversations.fold<int>(0, (sum, conv) => sum + (conv['unread_count'] as int? ?? 0));
  }

  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) return;

    setState(() => _isSearching = true);
    
    try {
      final currentUserId = supabase.auth.currentUser?.id;
      
      final response = await supabase
          .from('profiles')
          .select('id, username, full_name, profile_image_url, avatar_url')
          .ilike('username', '%$query%')
          .neq('id', currentUserId ?? '')
          .limit(20);

      if (mounted) {
        setState(() {
          _searchResults = response;
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error searching users: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  Future<void> _startConversation(String otherUserId) async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      // Check if conversation already exists between these two users
      final existingConv = await supabase
          .from('conversation_participants')
          .select('''
            conversation_id,
            conversations!inner(id)
          ''')
          .eq('user_id', currentUserId);

      String? conversationId;
      
      // Check if any of the current user's conversations also include the other user
      if (existingConv.isNotEmpty) {
        for (final conv in existingConv) {
          final convId = conv['conversation_id'];
          
          // Check if the other user is also a participant in this conversation
          final otherParticipant = await supabase
              .from('conversation_participants')
              .select('user_id')
              .eq('conversation_id', convId)
              .eq('user_id', otherUserId)
              .maybeSingle();
              
          if (otherParticipant != null) {
            conversationId = convId;
            break;
          }
        }
      }

      // If no existing conversation found, create a new one
      if (conversationId == null) {
        // Generate a proper UUID for the new conversation
        conversationId = const Uuid().v4();
        
        // Create new conversation
        await supabase.from('conversations').insert({
          'id': conversationId,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });

        // Add participants
        await supabase.from('conversation_participants').insert([
          {
            'conversation_id': conversationId,
            'user_id': currentUserId,
            'joined_at': DateTime.now().toIso8601String(),
          },
          {
            'conversation_id': conversationId,
            'user_id': otherUserId,
            'joined_at': DateTime.now().toIso8601String(),
          },
        ]);
      }

      // Navigate to chat screen
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              conversationId: conversationId!,
              otherUserId: otherUserId,
            ),
          ),
        ).then((_) => _loadConversations());
      }
    } catch (e) {
      _showSnackBar('Error starting conversation: $e', isError: true);
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

  String _getTimeAgo(String? createdAt) {
    if (createdAt == null) return '';
    
    final now = DateTime.now();
    final messageTime = DateTime.parse(createdAt);
    final difference = now.difference(messageTime);

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

  Widget _buildProfileAvatar(String? profilePictureUrl, String username) {
    if (profilePictureUrl != null && profilePictureUrl.isNotEmpty) {
      return Container(
        width: 50,
        height: 50,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: ClipOval(
          child: Image.network(
            profilePictureUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
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
      width: 50,
      height: 50,
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
            fontSize: 20,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E1A),
        elevation: 0,
        title: Row(
          children: [
            const Text(
              'Messages',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_totalUnreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _totalUnreadCount > 99 ? '99+' : _totalUnreadCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: const Color(0xFF1A1F2E),
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (context) => _buildNewMessageModal(),
              );
            },
            icon: const Icon(Icons.edit, color: Colors.white),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.blue),
            )
          : _conversations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.message_outlined,
                        size: 80,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No messages yet',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Start a conversation with someone',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _conversations.length,
                  itemBuilder: (context, index) {
                    return _buildConversationCard(_conversations[index]);
                  },
                ),
    );
  }

  Widget _buildConversationCard(Map<String, dynamic> conversation) {
    final otherParticipant = conversation['other_participant'];
    final profile = otherParticipant['profiles'];
    final username = profile['username'] ?? 'User';
    final fullName = profile['full_name'] ?? username;
    final profileImageUrl = profile['profile_image_url'] ?? profile['avatar_url'];
    final lastMessage = conversation['last_message'];
    final unreadCount = conversation['unread_count'] as int? ?? 0;
    
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              conversationId: conversation['id'],
              otherUserId: otherParticipant['user_id'],
            ),
          ),
        ).then((_) => _loadConversations());
      },
      child: Container(
        decoration: BoxDecoration(
          color: unreadCount > 0 ? const Color(0xFF1A1F2E) : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade900, width: 0.5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Stack(
                children: [
                  _buildProfileAvatar(profileImageUrl, username),
                  if (unreadCount > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            unreadCount > 9 ? '9+' : unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          fullName,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: unreadCount > 0 ? FontWeight.w900 : FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (lastMessage != null)
                          Text(
                            _getTimeAgo(lastMessage['created_at']),
                            style: TextStyle(
                              color: unreadCount > 0 ? Colors.blue : Colors.grey.shade600,
                              fontSize: 12,
                              fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lastMessage != null 
                          ? lastMessage['content'] ?? 'New message'
                          : 'Start a conversation',
                      style: TextStyle(
                        color: unreadCount > 0 ? Colors.white : Colors.grey.shade400,
                        fontSize: 14,
                        fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

  Widget _buildNewMessageModal() {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
              const Expanded(
                child: Text(
                  'New Message',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 48), // Balance the close button
            ],
          ),
          const SizedBox(height: 16),
          // Search bar
          TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search users...',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade800),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.blue),
              ),
              filled: true,
              fillColor: const Color(0xFF2A2F3E),
            ),
            autofocus: true,
          ),
          const SizedBox(height: 16),
          // Search results
          Expanded(
            child: _isSearching
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.blue),
                  )
                : _searchResults.isEmpty
                    ? Center(
                        child: Text(
                          _searchController.text.isEmpty
                              ? 'Search for users to start a conversation'
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
                          return _buildUserSearchResult(_searchResults[index]);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserSearchResult(Map<String, dynamic> user) {
    final username = user['username'] ?? 'User';
    final fullName = user['full_name'] ?? username;
    final profileImageUrl = user['profile_image_url'] ?? user['avatar_url'];

    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        _startConversation(user['id']);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade900, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            _buildProfileAvatar(profileImageUrl, username),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// Chat Screen for individual conversations
// Chat Screen for individual conversations
class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserId;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUserId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final supabase = SupabaseClientUtil.client;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _otherUserProfile;
  Map<String, dynamic>? _currentUserProfile;
  bool _isLoading = true;
  bool _isSending = false;
  RealtimeChannel? _realtimeChannel;
  final Uuid uuid = Uuid();

  @override
  void initState() {
    super.initState();
    _loadCurrentUserProfile();
    _loadOtherUserProfile();
    _loadMessages();
    _setupRealtime();
    _markMessagesAsRead(); // Mark messages as read when opening chat
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadCurrentUserProfile() async {
    try {
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) return;
      
      final response = await supabase
          .from('profiles')
          .select('id, username, full_name, profile_image_url, avatar_url')
          .eq('id', currentUserId)
          .single();
      
      if (mounted) {
        setState(() {
          _currentUserProfile = response;
        });
      }
    } catch (e) {
      // Handle error if needed
      _showSnackBar('Error loading current user profile: $e', isError: true);
    }
  }

  Future<void> _loadOtherUserProfile() async {
    try {
      final response = await supabase
          .from('profiles')
          .select('id, username, full_name, profile_image_url, avatar_url')
          .eq('id', widget.otherUserId)
          .single();
      
      if (mounted) {
        setState(() {
          _otherUserProfile = response;
        });
      }
    } catch (e) {
      _showSnackBar('Error loading user profile: $e', isError: true);
    }
  }

  Future<void> _setupRealtime() async {
    _realtimeChannel = supabase.channel('chat-${widget.conversationId}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'conversation_id',
          value: widget.conversationId,
        ),
        callback: (payload) {
          _loadMessages();
          _markMessagesAsRead(); // Mark new messages as read when they arrive
        },
      )
      ..subscribe();
  }

  Future<void> _loadMessages() async {
    try {
      final response = await supabase
          .from('messages')
          .select('''
            id,
            content,
            sender_id,
            created_at,
            sender:profiles(
              username,
              full_name,
              profile_image_url,
              avatar_url
            )
          ''')
          .eq('conversation_id', widget.conversationId)
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _messages = response;
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Error loading messages: $e', isError: true);
      }
    }
  }

  Future<void> _markMessagesAsRead() async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      // Get all messages in this conversation that are not sent by current user
      final messagesToMarkAsRead = await supabase
          .from('messages')
          .select('id')
          .eq('conversation_id', widget.conversationId)
          .neq('sender_id', currentUserId);

      if (messagesToMarkAsRead.isEmpty) return;

      // Check which messages are already marked as read
      final alreadyReadMessages = await supabase
          .from('message_read_status')
          .select('message_id')
          .eq('user_id', currentUserId)
          .inFilter('message_id', messagesToMarkAsRead.map((m) => m['id']).toList());

      final alreadyReadMessageIds = alreadyReadMessages.map((m) => m['message_id']).toSet();

      // Insert read status for unread messages
      final unreadMessages = messagesToMarkAsRead
          .where((m) => !alreadyReadMessageIds.contains(m['id']))
          .toList();

      if (unreadMessages.isNotEmpty) {
        final readStatusEntries = unreadMessages.map((message) => {
          'message_id': message['id'],
          'user_id': currentUserId,
          'read_at': DateTime.now().toIso8601String(),
        }).toList();

        await supabase.from('message_read_status').insert(readStatusEntries);
      }
    } catch (e) {
      // Handle error silently
    }
  }

  Future<void> _sendMessage() async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null || _messageController.text.trim().isEmpty) return;

    final messageText = _messageController.text.trim();
    _messageController.clear();

    setState(() => _isSending = true);

    try {
      final messageId = uuid.v4();
      
      // Insert the message
      await supabase.from('messages').insert({
        'id': messageId,
        'conversation_id': widget.conversationId,
        'sender_id': currentUserId,
        'content': messageText,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Mark the message as read by the sender immediately
      await supabase.from('message_read_status').insert({
        'message_id': messageId,
        'user_id': currentUserId,
        'read_at': DateTime.now().toIso8601String(),
      });

      // Update conversation's updated_at timestamp
      await supabase
          .from('conversations')
          .update({'updated_at': DateTime.now().toIso8601String()})
          .eq('id', widget.conversationId);

    } catch (e) {
      _showSnackBar('Error sending message: $e', isError: true);
    } finally {
      setState(() => _isSending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
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

  Widget _buildProfileAvatar(String? profilePictureUrl, String username, {double size = 32}) {
    if (profilePictureUrl != null && profilePictureUrl.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: ClipOval(
          child: Image.network(
            profilePictureUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _buildFallbackAvatar(username, size: size);
            },
          ),
        ),
      );
    } else {
      return _buildFallbackAvatar(username, size: size);
    }
  }

  Widget _buildFallbackAvatar(String username, {double size = 32}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade300,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          username.isNotEmpty ? username[0].toUpperCase() : 'U',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: size * 0.5,
          ),
        ),
      ),
    );
  }

  String _getTimeAgo(String? createdAt) {
    if (createdAt == null) return '';
    
    final now = DateTime.now();
    final messageTime = DateTime.parse(createdAt);
    final difference = now.difference(messageTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'now';
    }
  }

  @override
  Widget build(BuildContext context) {
    final otherUsername = _otherUserProfile?['username'] ?? 'User';
    final otherFullName = _otherUserProfile?['full_name'] ?? otherUsername;
    final otherProfileImage = _otherUserProfile?['profile_image_url'] ?? _otherUserProfile?['avatar_url'];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E1A),
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        title: Row(
          children: [
            _buildProfileAvatar(otherProfileImage, otherUsername),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  otherFullName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '@$otherUsername',
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
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.blue),
                  )
                : _messages.isEmpty
                    ? Center(
                        child: Text(
                          'Start the conversation!',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 16,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          return _buildMessageBubble(_messages[index]);
                        },
                      ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final currentUserId = supabase.auth.currentUser?.id;
    final isMyMessage = message['sender_id'] == currentUserId;
    final sender = message['sender'];
    final senderUsername = sender?['username'] ?? 'User';
    final senderProfileImage = sender?['profile_image_url'] ?? sender?['avatar_url'];
   
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isMyMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMyMessage) ...[
            _buildProfileAvatar(senderProfileImage, senderUsername),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.7,
              ),
              decoration: BoxDecoration(
                color: isMyMessage ? Colors.blue : const Color(0xFF2A2F3E),
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message['content'],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getTimeAgo(message['created_at']),
                    style: TextStyle(
                      color: isMyMessage ? Colors.blue.shade100 : Colors.grey.shade400,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMyMessage) ...[
            const SizedBox(width: 8),
            _buildProfileAvatar(
              _currentUserProfile?['profile_image_url'] ?? _currentUserProfile?['avatar_url'],
              _currentUserProfile?['username'] ?? 'You'
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E),
        border: Border(top: BorderSide(color: Colors.grey.shade900)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: const Color(0xFF2A2F3E),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (value) {
                setState(() {}); // Trigger rebuild to update send button state
              },
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _isSending || _messageController.text.trim().isEmpty ? null : _sendMessage,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _messageController.text.trim().isEmpty || _isSending
                    ? Colors.grey.shade600
                    : Colors.blue,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: _isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.send,
                        color: Colors.white,
                        size: 20,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}