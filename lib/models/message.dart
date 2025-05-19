class Message {
  final String id;
  final String chatSession;
  final Sender sender;
  final String content;
  final List<Attachment> attachments;
  final String status;
  final List<String> deletedFor;
  final ReplyTo? replyTo;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<MessageReaction> reactions;

  Message({
    required this.id,
    required this.chatSession,
    required this.sender,
    required this.content,
    required this.attachments,
    required this.status,
    required this.deletedFor,
    this.replyTo,
    required this.createdAt,
    required this.updatedAt,
    this.reactions = const [],
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['_id'],
      chatSession: json['chatSession'],
      sender: Sender.fromJson(json['sender']),
      content: json['content'],
      attachments: (json['attachments'] as List)
          .map((attachment) => Attachment.fromJson(attachment))
          .toList(),
      status: json['status'],
      deletedFor: List<String>.from(json['deletedFor'] ?? []),
      replyTo: json['replyTo'] != null ? ReplyTo.fromJson(json['replyTo']) : null,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      reactions: json['reactions'] != null
          ? (json['reactions'] as List)
              .map((reaction) => MessageReaction.fromJson(reaction))
              .toList()
          : [],
    );
  }
}

class Sender {
  final String id;
  final String firstName;
  final String lastName;
  final String dialCode;
  final String phone;
  final String? photo;

  Sender({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.dialCode,
    required this.phone,
    this.photo,
  });

  factory Sender.fromJson(Map<String, dynamic> json) {
    return Sender(
      id: json['_id'],
      firstName: json['firstName'],
      lastName: json['lastName'],
      dialCode: json['dialCode'],
      phone: json['phone'],
      photo: json['photo'],
    );
  }
}

class ReplyTo {
  final String id;
  final String? content;

  ReplyTo({
    required this.id,
    this.content,
  });

  factory ReplyTo.fromJson(Map<String, dynamic> json) {
    return ReplyTo(
      id: json['_id'],
      content: json['content'],
    );
  }
}

class Attachment {
  final String id;
  final String user;
  final String? type;
  final String url;
  final String name;
  final int size;
  final DateTime createdAt;
  final DateTime updatedAt;

  Attachment({
    required this.id,
    required this.user,
    this.type,
    required this.url,
    required this.name,
    required this.size,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      id: json['_id'],
      user: json['user'],
      type: json['type'],
      url: json['url'],
      name: json['name'],
      size: json['size'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }
}

class MessageReaction {
  final String reaction;
  final List<ReactionUser> users;

  MessageReaction({
    required this.reaction,
    this.users = const [],
  });

  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    return MessageReaction(
      reaction: json['reaction'],
      users:   (json['users'] as List)
          .map((user) => ReactionUser.fromJson(user))
          .toList(),
    );
  }
}

class ReactionUser {
  final String id;
  final String firstName;
  final String lastName;
  final String reaction;
  final DateTime reactedAt;

  ReactionUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.reaction,
    required this.reactedAt,
  });

  factory ReactionUser.fromJson(Map<String, dynamic> json) {
    return ReactionUser(
      id: json['_id'],
      firstName: json['firstName'],
      lastName: json['lastName'],
      reaction: json['reaction'],
      reactedAt: DateTime.parse(json['reactedAt']),
    );
  }
}
