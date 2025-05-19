class Post {
  final String id;
  final PostUser user;
  final PostAttachment attachment;
  final String? caption;
  final int likes;
  final List<String> seenBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  Post({
    required this.id,
    required this.user,
    required this.attachment,
    this.caption,
    required this.likes,
    required this.seenBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['_id'],
      user: PostUser.fromJson(json['user']),
      attachment: PostAttachment.fromJson(json['attachment']),
      caption: json['caption'],
      likes: json['likes'] ?? 0,
      seenBy: List<String>.from(json['seenBy'] ?? []),
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }
}

class PostUser {
  final String id;
  final String firstName;
  final String lastName;
  final String? username;
  final String dialCode;
  final String phone;
  final String? photo;

  PostUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.username,
    required this.dialCode,
    required this.phone,
    this.photo,
  });

  factory PostUser.fromJson(Map<String, dynamic> json) {
    return PostUser(
      id: json['_id'],
      firstName: json['firstName'],
      lastName: json['lastName'],
      username: json['username'],
      dialCode: json['dialCode'],
      phone: json['phone'],
      photo: json['photo'],
    );
  }
}

class PostAttachment {
  final String id;
  final String user;
  final String? type;
  final String url;
  final String name;
  final int size;
  final DateTime createdAt;
  final DateTime updatedAt;

  PostAttachment({
    required this.id,
    required this.user,
    this.type,
    required this.url,
    required this.name,
    required this.size,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PostAttachment.fromJson(Map<String, dynamic> json) {
    return PostAttachment(
      id: json['_id'],
      user: json['user'],
      type: json['type'],
      url: json['url'],
      name: json['name'],
      size: json['size'] ?? 0,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }
} 