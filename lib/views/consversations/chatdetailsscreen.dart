import 'package:chattingapp/constants/config.dart';
import 'package:chattingapp/models/chat_session.dart';
import 'package:chattingapp/models/message.dart';
import 'package:chattingapp/providers/chat_provider.dart';
import 'package:chattingapp/providers/group_provider.dart';
import 'package:chattingapp/services/auth_service.dart';
import 'package:chattingapp/services/socket_service.dart';
import 'package:chattingapp/views/contacts/contacts.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../providers/auth_provider.dart';
import '../../constants/colors.dart';
import '../camera/camera.dart';
import '../chatcalls/chatcalls.dart';
import '../createpoll/createpoll.dart';
import '../documents/documents.dart';
import '../gallery/gallery.dart';
import '../record/record.dart';
import '../sendlocation/sendlocation.dart';
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
  final SocketService _socketService = SocketService.instance;
  bool _isAttachmentSheetVisible = false;
  final TextEditingController _messageController = TextEditingController();
  ChatSession? session;
  List<File> _attachments = [];
  bool _isSending = false;
  bool _isTyping = false;
  Timer? _typingTimer;
  Message? _replyingTo;

  // Message list state
  List<Message> _messages = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 1;
  final ScrollController _scrollController = ScrollController();
  final int _limit = 20;

  @override
  void initState() {
    super.initState();
    _initializeSocket();
    _loadMessages();
    _scrollController.addListener(_scrollListener);
  }

  Future<void> _initializeSocket() async {
    try {
      await _socketService.initializeSocket();
      _socketService.joinChatSession(widget.session?.id ?? '');

      // Listen for new messages
      _socketService.onNewMessage((message) {
        if (mounted) {
          setState(() {
            _messages.insert(0, message);
          });
        }
      });

      // Listen for typing events
      _socketService.onTyping((userId, isTyping) {
        if (mounted && userId != context.read<AuthProvider>().userId) {
          setState(() {
            _isTyping = isTyping;
          });
        }
      });

      // Listen for reaction updates
      _socketService.onMessageReactionsUpdated((data) {
        if (mounted) {
          _updateMessageReactions(data['messageId'], data['reactions']);
        }
      });
    } catch (e) {
      print('Failed to initialize socket: $e');
    }
  }

  void _updateMessageReactions(String messageId, List<dynamic> reactions) {
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

    _socketService.emitTyping(widget.session?.id ?? '', true);

    _typingTimer = Timer(const Duration(seconds: 2), () {
      _socketService.emitTyping(widget.session?.id ?? '', false);
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _socketService.removeNewMessageListener();
    _socketService.removeTypingListener();
    _socketService.removeReactionUpdatesListener();
    _socketService.leaveChatSession(widget.session?.id ?? '');
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
      // final token = await context.read<AuthProvider>().getToken();

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

      if (response.statusCode == 200) {
        final data = json.decode(response.body)['data'];
        final List<Message> newMessages = (data['docs'] as List)
            .map((message) => Message.fromJson(message))
            .toList();

        setState(() {
          _messages.addAll(newMessages);
          // _messages.reverse();
          _hasMore = data['hasNextPage'] ?? false;
          _currentPage++;
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load messages');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load messages: ${e.toString()}')),
      );
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
        if (widget.session?.type == 'group') {
          context.read<GroupProvider>().fetchSessions(refresh: true);
        } else {
          context.read<ChatProvider>().fetchSessions(refresh: true);
        }
      } else {
        throw Exception('Failed to send message: $responseBody');
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
              icon: const Icon(Icons.video_call),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CallScreen()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.phone),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CallScreen()),
                );
              },
            ),
          ],
          title: Row(
            children: [
              CircleAvatar(
                backgroundImage: widget.session?.photo != null
                    ? NetworkImage(Config.getPhotoUrl(widget.session!.photo!))
                    : null,
                child: widget.session?.photo == null
                    ? Text(
                        widget.session?.title.substring(0, 1).toUpperCase() ??
                            '')
                    : null,
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.session?.title ?? 'Unknown',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
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
                    ),
                ],
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            if (_isTyping)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: const Text(
                  'Someone is typing...',
                  style: TextStyle(
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
                            senderImageUrl: isGroup && !isSent && message.sender.photo != null
                                ? Config.getPhotoUrl(message.sender.photo!)
                                : null,
                            senderName: '${message.sender.firstName} ${message.sender.lastName}',
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
        child: Container(
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
            crossAxisAlignment:
                isSent ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (isGroup && !isSent)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundImage:
                      senderImageUrl != null ? NetworkImage(senderImageUrl!) : null,
                      child: senderImageUrl == null
                          ? Text(senderName?.substring(0, 1).toUpperCase() ?? '')
                          : null,
                    )
                ),
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
                        onTap: () => _showReactionUsers(context, reaction),
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
      ),
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
                itemCount: reaction.users?.length,
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
