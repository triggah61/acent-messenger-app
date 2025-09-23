import 'package:acent_messenger/constants/config.dart';

import 'package:acent_messenger/models/chat_session.dart';
import 'package:acent_messenger/models/message.dart';
import 'package:acent_messenger/models/call.dart';
import 'package:acent_messenger/models/profile.dart';
// Removed unused imports - smart updates now handled by GlobalEventProvider
import 'package:acent_messenger/providers/global_event_provider.dart';
import 'package:acent_messenger/services/auth_service.dart';
import 'package:acent_messenger/services/call_service.dart';
import 'package:acent_messenger/services/pusher_service.dart';
import 'package:acent_messenger/views/contacts/contacts.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../providers/auth_provider.dart';
import '../../constants/colors.dart';
import '../camera/camera.dart';
import '../calls/agora_call_screen.dart';
import '../createpoll/createpoll.dart';
import '../documents/documents.dart';
import '../gallery/gallery.dart';
import '../record/record.dart';
import '../sendlocation/sendlocation.dart';
import '../voice_mode/voice_mode_screen.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'dart:convert';
import 'dart:async';

class Conversations extends StatefulWidget {
  final ChatSession? session;
  const Conversations({super.key, this.session});

  @override
  State<Conversations> createState() => _ConversationsState();
}

class _ConversationsState extends State<Conversations> {
  final AuthService _authService = AuthService();
  late final CallService _callService;
  final PusherService _pusherService = PusherService.instance;
  bool _isAttachmentSheetVisible = false;
  final TextEditingController _messageController = TextEditingController();
  ChatSession? session;
  List<File> _attachments = [];
  bool _isSending = false;
  bool _isTyping = false;
  Timer? _typingTimer;
  Timer? _typingIndicatorTimer;
  Map<String, String> _typingUsers = {}; // userId -> userName
  String? _currentUserId;
  Message? _replyingTo;

  // Message list state
  List<Message> _messages = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 1;
  final ScrollController _scrollController = ScrollController();
  final int _limit = 20;

  // Store listener references for proper cleanup
  Function(dynamic)? _newMessageListener;
  Function(dynamic)? _typingStartListener;
  Function(dynamic)? _typingStopListener;
  Function(dynamic)? _reactionUpdatesListener;

  @override
  void initState() {
    super.initState();

    // Initialize CallService
    _callService = CallService(_authService);

    // Set current active session for global event handling
    if (widget.session?.id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context
            .read<GlobalEventProvider>()
            .setCurrentActiveSession(widget.session!.id);
      });
    }

    _loadCurrentUserId();
    _initializeSocket();
    _loadMessages();
    _scrollController.addListener(_scrollListener);
  }

  Future<void> _loadCurrentUserId() async {
    try {
      final authProvider = context.read<AuthProvider>();
      _currentUserId = authProvider.userId ?? authProvider.profile?.id;
      print('Chat: Current user ID loaded: $_currentUserId');
    } catch (e) {
      print('Error loading current user ID: $e');
    }
  }

  Future<void> _initializeSocket() async {
    print('PusherService: Initializing socket called');
    try {
      // Wait for AuthProvider to finish loading if necessary
      final authProvider = context.read<AuthProvider>();
      if (authProvider.isLoading && !authProvider.isInitialized) {
        print('AuthProvider is still loading, waiting...');
        // Wait up to 5 seconds for auth provider to initialize
        int attempts = 0;
        while (authProvider.isLoading && attempts < 50) {
          // 50 attempts * 100ms = 5 seconds
          await Future.delayed(const Duration(milliseconds: 100));
          attempts++;
        }
      }

      // Get user ID from AuthProvider - try both methods for robustness
      final userId = authProvider.userId ?? authProvider.profile?.id;
      if (userId == null) {
        print(
            'Failed to get user ID for socket initialization - userId is null');
        print(
            'AuthProvider state: isLoading=${authProvider.isLoading}, isInitialized=${authProvider.isInitialized}, isAuthenticated=${authProvider.isAuthenticated}');
        print(
            'Profile ID: ${authProvider.profile?.id}, UserId: ${authProvider.userId}');
        return;
      }

      print('PusherService: Successfully retrieved user ID: $userId');

      // Ensure global socket is connected (this should already be done by GlobalEventProvider)
      // final result = await _pusherService.initializeGlobalSocket(userId);
      // if (!result) {
      //   print('Failed to initialize global socket');
      //   _pusherService.debugConnectionStatus();
      //   return;
      // }

      await _pusherService.initializeGlobalSocket(userId);

      print('PusherService: Socket initialized');

      print('PusherService: Joining to chat session ${widget.session?.id}');

      // Join chat session
      _pusherService.joinChatSession(widget.session?.id ?? '');

      // Set up event listeners for this specific chat
      // Listen for new messages
      _newMessageListener = (data) {
        print('Chat: New message received - $data');
        try {
          final message = Message.fromJson(data);
          final currentSessionId = widget.session?.id;

          // Only add message if it belongs to the current chat session
          if (mounted && message.chatSession == currentSessionId) {
            setState(() {
              _messages.insert(0, message);
            });
            print('Chat: Message added to current session $currentSessionId');
          } else {
            print(
                'Chat: Message ignored - belongs to session ${message.chatSession}, current session $currentSessionId');
          }
          // Note: Session list updates are now handled automatically by GlobalEventProvider
          // via smart update callbacks, so no need to manually refresh here
        } catch (e) {
          print('Error processing new message: $e');
        }
      };
      _pusherService.addChatEventListener('new_message', _newMessageListener!);

      // Listen for typing indicators
      _typingStartListener = (data) {
        print('Chat: Typing started - $data');
        try {
          final userId = data['userId'] as String?;
          final chatSessionId = data['chatSessionId'] as String?;
          final currentSessionId = widget.session?.id;

          // Only show typing indicator for other users in the current session
          if (mounted &&
              userId != null &&
              userId != _currentUserId &&
              chatSessionId == currentSessionId) {
            // Get user name from event data or session participants
            String userName = 'Someone';

            // First try to get user info from the event data
            if (data['userInfo'] != null) {
              final userInfo = data['userInfo'];
              final firstName = userInfo['firstName'] as String? ?? '';
              final lastName = userInfo['lastName'] as String? ?? '';
              userName = '$firstName $lastName'.trim();
              if (userName.isEmpty) {
                userName = userInfo['username'] as String? ?? 'Someone';
              }
            } else if (widget.session?.recipients != null) {
              // Fallback to session participants
              try {
                final typingUser = widget.session!.recipients
                    .firstWhere(
                      (participant) => participant.user.id == userId,
                    )
                    .user;
                userName =
                    '${typingUser.firstName ?? ''} ${typingUser.lastName ?? ''}'
                        .trim();
                if (userName.isEmpty) {
                  userName = 'Someone';
                }
              } catch (e) {
                // User not found in recipients, keep default 'Someone'
                print('Typing user not found in recipients: $e');
              }
            }

            setState(() {
              _typingUsers[userId] = userName;
              _isTyping = _typingUsers.isNotEmpty;
            });

            // Clear typing indicator after timeout
            _typingIndicatorTimer?.cancel();
            _typingIndicatorTimer = Timer(const Duration(seconds: 5), () {
              if (mounted) {
                setState(() {
                  _typingUsers.remove(userId);
                  _isTyping = _typingUsers.isNotEmpty;
                });
              }
            });
            print(
                'Chat: Typing indicator shown for user $userId in session $currentSessionId');
          } else {
            print(
                'Chat: Typing start ignored - user $userId, session $chatSessionId, current session $currentSessionId');
          }
        } catch (e) {
          print('Error in typing start listener: $e');
        }
      };
      _pusherService.addChatEventListener(
          'typing_start', _typingStartListener!);

      _typingStopListener = (data) {
        print('Chat: Typing stopped - $data');
        try {
          final userId = data['userId'] as String?;
          final chatSessionId = data['chatSessionId'] as String?;
          final currentSessionId = widget.session?.id;

          // Only handle typing stop for other users in the current session
          if (mounted &&
              userId != null &&
              userId != _currentUserId &&
              chatSessionId == currentSessionId) {
            setState(() {
              _typingUsers.remove(userId);
              _isTyping = _typingUsers.isNotEmpty;
            });

            // Cancel the timeout since user explicitly stopped typing
            if (_typingUsers.isEmpty) {
              _typingIndicatorTimer?.cancel();
            }
            print(
                'Chat: Typing stopped for user $userId in session $currentSessionId');
          } else {
            print(
                'Chat: Typing stop ignored - user $userId, session $chatSessionId, current session $currentSessionId');
          }
        } catch (e) {
          print('Error in typing stop listener: $e');
        }
      };
      _pusherService.addChatEventListener('stop_typing', _typingStopListener!);

      // Listen for reaction updates
      _reactionUpdatesListener = (data) {
        print('Chat: message_reactions_updated received - $data');
        try {
          final messageId = data['messageId'] as String?;
          final chatSessionId = data['chatSessionId'] as String?;
          final currentSessionId = widget.session?.id;

          // Only update reactions if the message belongs to the current chat session
          if (mounted &&
              messageId != null &&
              chatSessionId == currentSessionId) {
            _updateMessageReactions(messageId, data['reactions']);
            print(
                'Chat: Reactions updated for message $messageId in session $currentSessionId');
          } else {
            print(
                'Chat: Reaction update ignored - session $chatSessionId, current session $currentSessionId');
          }
        } catch (e) {
          print('Error in reaction updates listener: $e');
        }
      };
      _pusherService.addChatEventListener(
          'message_reactions_updated', _reactionUpdatesListener!);

      print('Chat: Socket initialization completed');
    } catch (e) {
      print('Failed to initialize socket for chat: $e');
      _pusherService.debugConnectionStatus();
    }
  }

  void _updateMessageReactions(String messageId, List<dynamic> reactions) {
    if (!mounted) return;

    setState(() {
      final messageIndex = _messages.indexWhere((m) => m.id == messageId);
      if (messageIndex != -1) {
        final updatedMessage = _messages[messageIndex];
        final updatedReactions =
            reactions.map((r) => MessageReaction.fromJson(r)).toList();

        _messages[messageIndex] = Message(
          id: updatedMessage.id,
          chatSession: updatedMessage.chatSession,
          sender: updatedMessage.sender,
          content: updatedMessage.content,
          attachments: updatedMessage.attachments,
          status: updatedMessage.status,
          deletedFor: updatedMessage.deletedFor,
          replyTo: updatedMessage.replyTo,
          createdAt: updatedMessage.createdAt,
          updatedAt: updatedMessage.updatedAt,
          reactions: updatedReactions,
        );
      }
    });
  }

  void _handleTyping() {
    if (_typingTimer?.isActive ?? false) {
      _typingTimer?.cancel();
    }

    _pusherService.emitChatTyping(widget.session?.id ?? '', true);

    _typingTimer = Timer(const Duration(seconds: 2), () {
      _pusherService.emitChatTyping(widget.session?.id ?? '', false);
    });
  }

  String _getTypingText() {
    if (_typingUsers.isEmpty) return '';

    final userNames = _typingUsers.values.toList();

    if (userNames.length == 1) {
      return '${userNames.first} is typing...';
    } else if (userNames.length == 2) {
      return '${userNames.first} and ${userNames.last} are typing...';
    } else if (userNames.length <= 3) {
      return '${userNames.take(2).join(', ')} and ${userNames.length - 2} other${userNames.length > 3 ? 's' : ''} are typing...';
    } else {
      return 'Several people are typing...';
    }
  }

  @override
  void dispose() {
    // Clear current active session
    context.read<GlobalEventProvider>().clearCurrentActiveSession();

    _typingTimer?.cancel();
    _typingIndicatorTimer?.cancel();

    // Remove chat event listeners
    if (_newMessageListener != null) {
      _pusherService.removeChatEventListener(
          'new_message', _newMessageListener!);
    }
    if (_typingStartListener != null) {
      _pusherService.removeChatEventListener(
          'typing_start', _typingStartListener!);
    }
    if (_typingStopListener != null) {
      _pusherService.removeChatEventListener(
          'stop_typing', _typingStopListener!);
    }
    if (_reactionUpdatesListener != null) {
      _pusherService.removeChatEventListener(
          'message_reactions_updated', _reactionUpdatesListener!);
    }

    // Leave chat session
    _pusherService.leaveChatSession(widget.session?.id ?? '');

    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels ==
        _scrollController.position.maxScrollExtent) {
      if (!_isLoading && _hasMore) {
        _loadMessages();
      }
    }
  }

  Future<void> _loadMessages() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No authentication token available');
      }

      final response = await http.get(
        Uri.parse(
            '${Config.baseApiUrl}/user/chat/getMessages/${widget.session?.id}?page=$_currentPage&limit=$_limit'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      print('Message loading response status: ${response.statusCode}');
      print('Message loading response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        // Check if response has the expected structure
        if (responseData['data'] == null) {
          throw Exception('Invalid response structure: missing data field');
        }

        final data = responseData['data'];

        // Check if docs field exists
        if (data['docs'] == null) {
          throw Exception('Invalid response structure: missing docs field');
        }

        final List<Message> newMessages = [];

        // Safely parse each message with error handling
        for (var messageJson in (data['docs'] as List)) {
          try {
            final message = Message.fromJson(messageJson);
            newMessages.add(message);
          } catch (e) {
            print('Error parsing message: $e');
            print('Message JSON: $messageJson');
            // Continue with other messages instead of failing completely
          }
        }

        setState(() {
          _messages.addAll(newMessages);
          _hasMore = data['hasNextPage'] ?? false;
          _currentPage++;
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load messages: HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('Error in _loadMessages: $e');
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load messages: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty && _attachments.isEmpty) return;

    setState(() {
      _isSending = true;
    });

    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No authentication token available');
      }

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${Config.baseApiUrl}/user/chat/sendMessage'),
      );

      // Add headers
      request.headers.addAll({
        'Authorization': 'Bearer $token',
      });

      // Add form fields
      request.fields['chatSessionId'] = widget.session?.id ?? '';
      request.fields['message'] = _messageController.text.trim();

      // Add reply data if replying
      if (_replyingTo != null) {
        request.fields['replyTo'] = _replyingTo!.id;
      }

      // Add attachments if any
      for (var attachment in _attachments) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'attachments',
            attachment.path,
          ),
        );
      }

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        // Clear message, attachments, and reply after successful send
        _messageController.clear();
        setState(() {
          _attachments = [];
          _replyingTo = null;
        });
        // No need to manually refresh sessions - the smart update mechanism
        // will handle this automatically when the message is received via Pusher
      } else {
        final errorData = json.decode(responseBody);
        throw Exception("Failed to send message: ${errorData['message']}");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  void _cancelReply() {
    setState(() {
      _replyingTo = null;
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: source);
      if (image != null) {
        setState(() {
          _attachments.add(File(image.path));
        });
        _hideAttachmentSheet();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: ${e.toString()}')),
      );
    }
  }

  Future<void> _pickFile() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? file = await picker.pickMedia();
      if (file != null) {
        setState(() {
          _attachments.add(File(file.path));
        });
        _hideAttachmentSheet();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick file: ${e.toString()}')),
      );
    }
  }

  void _toggleAttachmentSheet() {
    setState(() {
      _isAttachmentSheetVisible = !_isAttachmentSheetVisible;
    });
  }

  void _hideAttachmentSheet() {
    setState(() {
      _isAttachmentSheetVisible = false;
    });
  }

  void _handleCameraAttachment() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) =>
              CameraScreen()), // Replace CameraScreen with your actual camera widget/route
    );
  }

  void _handleRecordAttachment() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) =>
              RecordScreen()), // Replace RecordScreen with your actual record widget/route
    );
  }

  void _handlePollAttachment() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) =>
              CreatePollScreen()), // Replace RecordScreen with your actual record widget/route
    );
  }

  void _handleContactAttachment() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) =>
              ContactsScreen()), // Replace ContactScreen with your actual contact widget/route
    );
  }

  void _handleGalleryAttachment() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) =>
              GalleryScreen()), // Replace GalleryScreen with your actual gallery widget/route
    );
  }

  void _handleLocationAttachment() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) =>
              LocationScreen()), // Replace LocationScreen with your actual location widget/route
    );
  }

  void _handleDocumentAttachment() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) =>
              DocumentScreen()), // Replace DocumentScreen with your actual document widget/route
    );
  }

  /// Initiate a video call
  Future<void> _initiateVideoCall() async {
    await _initiateCall('video');
  }

  /// Initiate a voice call
  Future<void> _initiateVoiceCall() async {
    await _initiateCall('voice');
  }

  /// Main call initiation method
  Future<void> _initiateCall(String callType) async {
    try {
      if (widget.session == null) {
        _showErrorMessage('No active chat session');
        return;
      }

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Get participant IDs based on chat session type
      List<String> participantIds = [];

      if (widget.session!.type == 'group') {
        // For group chats, include all recipients
        participantIds = widget.session!.recipients
            .map((recipient) => recipient.user.id)
            .toList();
      } else {
        // For individual chats, get the other user
        if (widget.session!.otherUser?.id != null) {
          participantIds = [widget.session!.otherUser!.id];
        } else {
          throw Exception('Unable to identify call recipient');
        }
      }

      // Initiate the call
      final result = await _callService.initiateCall(
        participantIds: participantIds,
        type: callType,
        chatSessionId: widget.session!.id,
      );

      // Hide loading indicator
      Navigator.of(context).pop();

      if (result['success'] == true) {
        final call = result['call'] as Call;
        final channelName = result['channelName'] as String;

        // Navigate to call screen with the call details
        await _navigateToCallScreen(call, channelName);

        _showSuccessMessage('Call initiated successfully');
      } else {
        _showErrorMessage(result['error'] ?? 'Failed to initiate call');
      }
    } catch (e) {
      // Hide loading indicator if still showing
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      print('Error initiating call: $e');
      _showErrorMessage('Failed to initiate call: ${e.toString()}');
    }
  }

  /// Navigate to the actual call screen
  Future<void> _navigateToCallScreen(Call call, String channelName) async {
    try {
      // Get Agora token for the call
      final agoraToken = await _callService.getCallToken(call.id);

      if (agoraToken != null) {
        // Navigate to the Agora call screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AgoraCallScreen(
              call: call,
              channelName: channelName,
              agoraToken: agoraToken.token,
              agoraUid: agoraToken.integerUid,
              isIncoming: false,
            ),
          ),
        );
      } else {
        throw Exception('Failed to get call token');
      }
    } catch (e) {
      print('Error navigating to call screen: $e');
      _showErrorMessage('Failed to start call: ${e.toString()}');
    }
  }

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Navigate to voice mode
  void _enterVoiceMode() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VoiceModeScreen(session: widget.session),
      ),
    );
  }

  void _showConversationInfo() {
    if (widget.session == null) return;

    if (widget.session!.type == 'group') {
      _showGroupInfoModal();
    } else {
      _showUserInfoModal();
    }
  }

  void _showUserInfoModal() {
    final otherUser = widget.session?.otherUser;
    if (otherUser == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => UserInfoModal(user: otherUser),
    );
  }

  void _showGroupInfoModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GroupInfoModal(session: widget.session!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileInfo =
        Provider.of<AuthProvider>(context, listen: false).profile;
    return GestureDetector(
      onTap: () {
        // Dismiss keyboard if open
        FocusScope.of(context).unfocus();
        // Hide attachment sheet if visible
        if (_isAttachmentSheetVisible) {
          _hideAttachmentSheet();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.record_voice_over),
              onPressed: _enterVoiceMode,
              tooltip: 'Voice mode',
            ),
            IconButton(
              icon: const Icon(Icons.video_call),
              onPressed: _initiateVideoCall,
              tooltip: 'Start video call',
            ),
            IconButton(
              icon: const Icon(Icons.phone),
              onPressed: _initiateVoiceCall,
              tooltip: 'Start voice call',
            ),
          ],
          title: GestureDetector(
            onTap: _showConversationInfo,
            child: Row(
              children: [
                CircleAvatar(
                  backgroundImage: widget.session?.photo != null
                      ? NetworkImage(Config.getPhotoUrl(widget.session!.photo!))
                      : null,
                  child: widget.session?.photo == null
                      ? Text(_getSessionInitials(widget.session?.title))
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.session?.title ?? 'Unknown',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.session?.type == 'group')
                        Text(
                          '${widget.session?.recipients.length ?? 0} participants',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        )
                      else
                        Text(
                          '${widget.session?.otherUser?.dialCode} ${widget.session?.otherUser?.phone}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                // const Icon(
                //   Icons.info_outline,
                //   size: 20,
                //   color: Colors.grey,
                // ),
              ],
            ),
          ),
        ),
        body: Column(
          children: [
            if (_isTyping)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  _getTypingText(),
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ),
            if (_replyingTo != null)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.grey[300]!,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 40,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Replying to ${_replyingTo!.sender.firstName}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          Text(
                            _replyingTo!.content.isNotEmpty
                                ? _replyingTo!.content
                                : 'Photo',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _cancelReply,
                    ),
                  ],
                ),
              ),
            if (_attachments.isNotEmpty)
              Container(
                height: 100,
                padding: const EdgeInsets.all(8),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _attachments.length,
                  itemBuilder: (context, index) {
                    return Stack(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            image: DecorationImage(
                              image: FileImage(_attachments[index]),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                _attachments.removeAt(index);
                              });
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            Expanded(
              child: _isLoading && _messages.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _messages.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _messages.length) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(8.0),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }

                        final message = _messages[index];
                        final isSent = message.sender.id == profileInfo?.id;
                        final isGroup = widget.session?.type == 'group';

                        return Dismissible(
                          key: Key(message.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            color: Colors.blue,
                            child: const Icon(
                              Icons.reply,
                              color: Colors.white,
                            ),
                          ),
                          confirmDismiss: (direction) async {
                            setState(() {
                              _replyingTo = message;
                            });
                            return false; // Prevent actual dismissal
                          },
                          child: MessageBubble(
                            message: message.content,
                            isSent: isSent,
                            time: timeago.format(message.createdAt),
                            attachments: message.attachments,
                            messageId: message.id,
                            reactions: message.reactions,
                            replyTo: message.replyTo,
                            senderImageUrl: isGroup &&
                                    !isSent &&
                                    message.sender.photo != null
                                ? Config.getPhotoUrl(message.sender.photo!)
                                : null,
                            senderName:
                                '${message.sender.firstName} ${message.sender.lastName}',
                            isGroup: isGroup,
                          ),
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.bgColor,
                boxShadow: [
                  BoxShadow(
                    color: Color.fromARGB((0.2 * 255).toInt(), 128, 128, 128),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline,
                        color: Colors.grey, size: 30),
                    onPressed: _toggleAttachmentSheet,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: TextField(
                        controller: _messageController,
                        onChanged: (_) => _handleTyping(),
                        decoration: InputDecoration(
                          hintText: 'Type a message ...',
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _isSending ? null : _sendMessage,
                    icon: _isSending
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.send,
                            color: Colors.blue,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomSheet:
            _isAttachmentSheetVisible ? _buildAttachmentSheet(context) : null,
      ),
    );
  }

  Widget _buildAttachmentSheet(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Color.fromARGB((0.3 * 255).toInt(), 128, 128, 128),
            spreadRadius: 2,
            blurRadius: 5,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 20,
        runSpacing: 20,
        children: [
          _AttachmentButton(
            icon: Icons.poll,
            label: 'Poll',
            onPressed: () {
              _hideAttachmentSheet();
              _handlePollAttachment();
            },
          ),
          _AttachmentButton(
            icon: Icons.person,
            label: 'Contact',
            onPressed: () {
              _hideAttachmentSheet();
              _handleContactAttachment();
            },
          ),
          _AttachmentButton(
            icon: Icons.location_on,
            label: 'My Location',
            onPressed: () {
              _hideAttachmentSheet();
              _handleLocationAttachment();
            },
          ),
          _AttachmentButton(
            icon: Icons.insert_drive_file,
            label: 'Document',
            onPressed: () {
              _hideAttachmentSheet();
              _pickFile();
            },
          ),
          _AttachmentButton(
            icon: Icons.camera_alt,
            label: 'Camera',
            onPressed: () {
              _hideAttachmentSheet();
              _pickImage(ImageSource.camera);
            },
          ),
          _AttachmentButton(
            icon: Icons.mic,
            label: 'Record',
            onPressed: () {
              _hideAttachmentSheet();
              _handleRecordAttachment();
            },
          ),
          _AttachmentButton(
            icon: Icons.image,
            label: 'Gallery',
            onPressed: () {
              _hideAttachmentSheet();
              _pickImage(ImageSource.gallery);
            },
          ),
        ],
      ),
    );
  }

  String _getSessionInitials(String? title) {
    if (title == null || title.trim().isEmpty) {
      return '?';
    }

    // Split by spaces and filter out empty strings
    final words =
        title.trim().split(' ').where((word) => word.isNotEmpty).toList();

    if (words.isEmpty) {
      return '?';
    } else if (words.length == 1) {
      return words[0].isNotEmpty ? words[0][0].toUpperCase() : '?';
    } else {
      // Take first letter of first two words
      String first = words[0].isNotEmpty ? words[0][0].toUpperCase() : '';
      String second = words[1].isNotEmpty ? words[1][0].toUpperCase() : '';
      return '$first$second';
    }
  }
}

class _AttachmentButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _AttachmentButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onPressed,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: Colors.blue, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }
}

class MessageBubble extends StatelessWidget {
  final String message;
  final bool isSent;
  final String time;
  final List<Attachment> attachments;
  final String messageId;
  final List<MessageReaction> reactions;
  final ReplyTo? replyTo;

  final String? senderImageUrl;
  final String? senderName;
  final bool isGroup;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isSent,
    required this.time,
    required this.messageId,
    this.attachments = const [],
    this.reactions = const [],
    this.replyTo,
    this.senderImageUrl,
    this.senderName,
    this.isGroup = false,
  });

  @override
  Widget build(BuildContext context) {
    Color bubbleColor = isSent ? const Color(0xFFDCF8C6) : Colors.white;
    Color textColor = Colors.black87;
    Color timeColor = Colors.grey[600]!;

    return GestureDetector(
      onLongPress: () {
        _showReactionPicker(context);
      },
      child: Align(
          alignment: isSent ? Alignment.bottomRight : Alignment.bottomLeft,
          child: Column(
            children: [
              // Text(
              //   'Replying to message',
              //   style: TextStyle(
              //     color: Colors.grey[600],
              //     fontSize: 12,
              //     fontWeight: FontWeight.bold,
              //   ),
              // ),
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: !isSent
                        ? const Radius.circular(18)
                        : const Radius.circular(12),
                    topRight: isSent
                        ? const Radius.circular(18)
                        : const Radius.circular(12),
                    bottomLeft: const Radius.circular(18),
                    bottomRight: const Radius.circular(18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color.fromARGB((0.1 * 255).toInt(), 128, 128, 128),
                      spreadRadius: 0.5,
                      blurRadius: 1,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: isSent
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (isGroup && !isSent)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: CircleAvatar(
                            radius: 16,
                            backgroundImage: senderImageUrl != null
                                ? NetworkImage(senderImageUrl!)
                                : null,
                            child: senderImageUrl == null
                                ? Text(_getSenderInitials(senderName))
                                : null,
                          )),
                    if (replyTo != null)
                      Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Replying to message',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (replyTo!.content != null)
                              Text(
                                replyTo!.content!,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    if (message.isNotEmpty)
                      Text(
                        message,
                        style: TextStyle(
                          color: textColor,
                        ),
                      ),
                    if (attachments.isNotEmpty)
                      ...attachments
                          .map((attachment) => Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    attachment.url,
                                    width: 200,
                                    height: 200,
                                    fit: BoxFit.cover,
                                    loadingBuilder:
                                        (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return Container(
                                        width: 200,
                                        height: 200,
                                        color: Colors.grey[200],
                                        child: const Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      );
                                    },
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        width: 200,
                                        height: 200,
                                        color: Colors.grey[200],
                                        child: const Center(
                                          child: Icon(Icons.error),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ))
                          .toList(),
                    if (reactions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Wrap(
                          spacing: 4,
                          children: reactions.map((reaction) {
                            return GestureDetector(
                              onTap: () =>
                                  _showReactionUsers(context, reaction),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _getReactionEmoji(reaction.reaction),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    if (reaction.users.length > 1)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 2),
                                        child: Text(
                                          reaction.users.length.toString(),
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      time,
                      style: TextStyle(
                        color: timeColor,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          )),
    );
  }

  void _showReactionPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ReactionPicker(
        messageId: messageId,
        onReactionSelected: (reactionType) async {
          try {
            final token = await AuthService().getToken();
            if (token == null) {
              throw Exception('No authentication token available');
            }

            final response = await http.post(
              Uri.parse('${Config.baseApiUrl}/user/chat/toggleReaction'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: json.encode({
                'messageId': messageId,
                'reactionType': reactionType,
              }),
            );

            if (response.statusCode != 200) {
              throw Exception('Failed to add reaction');
            }

            // Close the reaction picker
            Navigator.pop(context);
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text('Failed to add reaction: ${e.toString()}')),
            );
          }
        },
      ),
    );
  }

  void _showReactionUsers(BuildContext context, MessageReaction reaction) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _getReactionEmoji(reaction.reaction),
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(width: 8),
                Text(
                  '${reaction.reaction.toUpperCase()} Reactions',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: reaction.users.length,
                itemBuilder: (context, index) {
                  final user = reaction.users[index];
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(user.firstName[0]),
                    ),
                    title: Text('${user.firstName} ${user.lastName}'),
                    subtitle: Text(
                      timeago.format(user.reactedAt),
                      style: const TextStyle(fontSize: 12),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getReactionEmoji(String type) {
    switch (type) {
      case 'like':
        return '👍';
      case 'love':
        return '❤️';
      case 'laugh':
        return '😂';
      case 'sad':
        return '😢';
      case 'angry':
        return '😠';
      case 'wow':
        return '😮';
      case 'cry':
        return '😭';
      default:
        return '👍';
    }
  }

  String _getSenderInitials(String? name) {
    if (name == null || name.trim().isEmpty) {
      return '?';
    }

    // Split by spaces and filter out empty strings
    final words =
        name.trim().split(' ').where((word) => word.isNotEmpty).toList();

    if (words.isEmpty) {
      return '?';
    } else if (words.length == 1) {
      return words[0].isNotEmpty ? words[0][0].toUpperCase() : '?';
    } else {
      // Take first letter of first two words
      String first = words[0].isNotEmpty ? words[0][0].toUpperCase() : '';
      String second = words[1].isNotEmpty ? words[1][0].toUpperCase() : '';
      return '$first$second';
    }
  }
}

/// User Information Modal for Personal Chats
class UserInfoModal extends StatelessWidget {
  final Profile user;

  const UserInfoModal({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),

            // User Avatar
            Stack(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundImage: user.photo != null
                      ? NetworkImage(Config.getPhotoUrl(user.photo!))
                      : null,
                  child: user.photo == null
                      ? Text(
                          _getUserInitials(user),
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // User Name
            Text(
              '${user.firstName ?? ''} ${user.lastName ?? ''}'.trim().isNotEmpty
                  ? '${user.firstName ?? ''} ${user.lastName ?? ''}'.trim()
                  : user.username ?? 'Unknown User',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            // User Status
            if (user.status != null)
              Text(
                user.status!,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),

            const SizedBox(height: 24),

            // User Information Cards
            _buildInfoCard(
              icon: Icons.phone,
              title: 'Phone',
              value: '${user.dialCode ?? ''} ${user.phone}'.trim(),
            ),

            if (user.username != null)
              _buildInfoCard(
                icon: Icons.alternate_email,
                title: 'Username',
                value: user.username!,
              ),

            if (user.gender != null)
              _buildInfoCard(
                icon: Icons.person,
                title: 'Gender',
                value: user.gender!.toUpperCase(),
              ),

            if (user.dob != null)
              _buildInfoCard(
                icon: Icons.cake,
                title: 'Date of Birth',
                value: _formatDate(user.dob!),
              ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getUserInitials(Profile user) {
    final firstName = user.firstName ?? '';
    final lastName = user.lastName ?? '';

    if (firstName.isNotEmpty && lastName.isNotEmpty) {
      return '${firstName[0]}${lastName[0]}'.toUpperCase();
    } else if (firstName.isNotEmpty) {
      return firstName[0].toUpperCase();
    } else if (user.username != null && user.username!.isNotEmpty) {
      return user.username![0].toUpperCase();
    }
    return '?';
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }
}

/// Group Information Modal for Group Chats
class GroupInfoModal extends StatelessWidget {
  final ChatSession session;

  const GroupInfoModal({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),

            // Group Avatar
            CircleAvatar(
              radius: 50,
              backgroundImage: session.photo != null
                  ? NetworkImage(Config.getPhotoUrl(session.photo!))
                  : null,
              child: session.photo == null
                  ? Text(
                      _getGroupInitials(session.title),
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold),
                    )
                  : null,
            ),

            const SizedBox(height: 16),

            // Group Name
            Text(
              session.title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            // Group Info
            Text(
              'Group • ${session.recipients.length} participants',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // Group Description Card
            _buildGroupInfoCard(),

            const SizedBox(height: 24),

            // Participants Section
            Row(
              children: [
                Icon(Icons.group, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Participants (${session.recipients.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Participants List
            ...session.recipients
                .map((recipient) => _buildParticipantTile(recipient)),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.blue, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Group Information',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Created ${_formatCreatedDate(session.createdAt)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantTile(Recipient recipient) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundImage: recipient.user.photo != null
                ? NetworkImage(Config.getPhotoUrl(recipient.user.photo!))
                : null,
            child: recipient.user.photo == null
                ? Text(
                    _getParticipantInitials(recipient.user),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${recipient.user.firstName} ${recipient.user.lastName}'
                          .trim()
                          .isNotEmpty
                      ? '${recipient.user.firstName} ${recipient.user.lastName}'
                          .trim()
                      : 'Unknown User',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${recipient.user.dialCode} ${recipient.user.phone}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          if (recipient.role == 'admin')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Admin',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.blue[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _getGroupInitials(String title) {
    if (title.trim().isEmpty) return '?';

    final words =
        title.trim().split(' ').where((word) => word.isNotEmpty).toList();

    if (words.isEmpty) {
      return '?';
    } else if (words.length == 1) {
      return words[0].isNotEmpty ? words[0][0].toUpperCase() : '?';
    } else {
      String first = words[0].isNotEmpty ? words[0][0].toUpperCase() : '';
      String second = words[1].isNotEmpty ? words[1][0].toUpperCase() : '';
      return '$first$second';
    }
  }

  String _getParticipantInitials(Sender user) {
    final firstName = user.firstName;
    final lastName = user.lastName;

    if (firstName.isNotEmpty && lastName.isNotEmpty) {
      return '${firstName[0]}${lastName[0]}'.toUpperCase();
    } else if (firstName.isNotEmpty) {
      return firstName[0].toUpperCase();
    }
    return '?';
  }

  String _formatCreatedDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays < 1) {
      return 'today';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      return '${(difference.inDays / 7).round()} weeks ago';
    } else if (difference.inDays < 365) {
      return '${(difference.inDays / 30).round()} months ago';
    } else {
      return '${(difference.inDays / 365).round()} years ago';
    }
  }
}

class ReactionPicker extends StatelessWidget {
  final String messageId;
  final Function(String) onReactionSelected;

  const ReactionPicker({
    super.key,
    required this.messageId,
    required this.onReactionSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Add Reaction',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 20,
            runSpacing: 20,
            alignment: WrapAlignment.center,
            children: [
              _ReactionButton(
                emoji: '👍',
                label: 'Like',
                onTap: () => onReactionSelected('like'),
              ),
              _ReactionButton(
                emoji: '❤️',
                label: 'Love',
                onTap: () => onReactionSelected('love'),
              ),
              _ReactionButton(
                emoji: '😂',
                label: 'Laugh',
                onTap: () => onReactionSelected('laugh'),
              ),
              _ReactionButton(
                emoji: '😢',
                label: 'Sad',
                onTap: () => onReactionSelected('sad'),
              ),
              _ReactionButton(
                emoji: '😠',
                label: 'Angry',
                onTap: () => onReactionSelected('angry'),
              ),
              _ReactionButton(
                emoji: '😮',
                label: 'Wow',
                onTap: () => onReactionSelected('wow'),
              ),
              _ReactionButton(
                emoji: '😭',
                label: 'Cry',
                onTap: () => onReactionSelected('cry'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReactionButton extends StatelessWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;

  const _ReactionButton({
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(25),
            ),
            child: Center(
              child: Text(
                emoji,
                style: const TextStyle(fontSize: 24),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}
