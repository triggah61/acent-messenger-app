class Profile {
  final String id;
  final String phoneNumber;
  final String? name;
  final String? email;
  final String? avatar;

  Profile({
    required this.id,
    required this.phoneNumber,
    this.name,
    this.email,
    this.avatar,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'],
      phoneNumber: json['phone_number'],
      name: json['name'],
      email: json['email'],
      avatar: json['avatar'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phone_number': phoneNumber,
      'name': name,
      'email': email,
      'avatar': avatar,
    };
  }
} 