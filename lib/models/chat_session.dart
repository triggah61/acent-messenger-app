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
    return ChatSession(
      id: json['_id'] ?? '',
      title: json['title'] ?? '',
      type: json['type'] ?? 'direct',
      lastMessage: json['lastMessage'] != null ? LastMessage.fromJson(json['lastMessage']) : null,
      createdBy: json['createdBy'],
      otherUser: json['otherUser'] != null ? Profile.fromJson(json['otherUser']) : null,
      status: json['status'] ?? 'active',
      recipients: (json['receipients'] as List? ?? []).map((r) => Recipient.fromJson(r)).toList(),
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
    return Recipient(
      user: Sender.fromJson(json['user'] ?? {}),
      role: json['role'] ?? 'member',
      isMute: json['isMute'] ?? false,
      status: json['status'] ?? 'active',
      id: json['_id'] ?? '',
    );
  }
} 