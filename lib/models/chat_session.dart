import 'package:acent_messenger/models/message.dart';
import 'package:acent_messenger/models/profile.dart';

class ChatSession {
  final String id;
  final String title;
  final String type;
  final LastMessage? lastMessage;
  final String? createdBy;
  final Profile? otherUser;
  final String status;
  final List<Recipient> recipients;
  final String? photo;
  final DateTime createdAt;

  ChatSession({
    required this.id,
    required this.title,
    required this.type,
    this.lastMessage,
    this.createdBy,
    this.otherUser,
    required this.status,
    required this.recipients,
    this.photo,
    required this.createdAt,
  });

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    // Handle otherUser field properly for both personal and group sessions
    Profile? otherUser;
    if (json['otherUser'] != null &&
        json['otherUser'] is Map<String, dynamic>) {
      final otherUserMap = json['otherUser'] as Map<String, dynamic>;
      // Only create Profile if it has the required fields (not empty object)
      if (otherUserMap.containsKey('_id') &&
          otherUserMap['_id'] != null &&
          otherUserMap.containsKey('phone') &&
          otherUserMap['phone'] != null) {
        otherUser = Profile.fromJson(otherUserMap);
      }
    }

    return ChatSession(
      id: json['_id'] ?? '',
      title: json['title'] ?? '',
      type: json['type'] ?? 'direct',
      lastMessage: json['lastMessage'] != null
          ? LastMessage.fromJson(json['lastMessage'])
          : null,
      createdBy: json['createdBy'],
      otherUser: otherUser,
      status: json['status'] ?? 'active',
      recipients: (json['receipients'] as List? ?? [])
          .map((r) => Recipient.fromJson(r))
          .toList(),
      photo: json['photo'],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }
}

class LastMessage {
  final String id;
  final String sender;
  final String content;
  final List<dynamic> attachments;
  final String status;
  final dynamic replyTo;
  final DateTime createdAt;

  LastMessage({
    required this.id,
    required this.sender,
    required this.content,
    required this.attachments,
    required this.status,
    this.replyTo,
    required this.createdAt,
  });

  factory LastMessage.fromJson(Map<String, dynamic> json) {
    return LastMessage(
      id: json['_id'] ?? '',
      sender: json['sender'] ?? '',
      content: json['content'] ?? '',
      attachments: json['attachments'] ?? [],
      status: json['status'] ?? 'sent',
      // replyTo: json['replyTo'],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }
}

class Recipient {
  final Sender user;
  final String role;
  final bool isMute;
  final String status;
  final String id;

  Recipient({
    required this.user,
    required this.role,
    required this.isMute,
    required this.status,
    required this.id,
  });

  factory Recipient.fromJson(Map<String, dynamic> json) {
    // Handle user field safely - it should be a Map but sometimes might be String or null
    Sender user;
    try {
      final userData = json['user'];
      if (userData is Map<String, dynamic>) {
        user = Sender.fromJson(userData);
      } else if (userData is String) {
        // If user is just an ID string, create a minimal Sender object
        user = Sender(
          id: userData,
          firstName: 'Unknown',
          lastName: 'User',
          dialCode: '',
          phone: '',
          photo: null,
        );
      } else {
        // Fallback for null or unexpected data types
        user = Sender.fromJson({});
      }
    } catch (e) {
      print('Error parsing recipient user data: $e');
      // Create a fallback Sender if parsing fails
      user = Sender(
        id: '',
        firstName: 'Unknown',
        lastName: 'User',
        dialCode: '',
        phone: '',
        photo: null,
      );
    }

    return Recipient(
      user: user,
      role: json['role'] ?? 'member',
      isMute: json['isMute'] ?? false,
      status: json['status'] ?? 'active',
      id: json['_id'] ?? '',
    );
  }
}
