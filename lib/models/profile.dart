class Profile {
  final String id;
  final String phone;
  final String? dialCode;
  final String? firstName;
  final String? lastName;
  final String? status;
  final String? photo;

  Profile({
    required this.id,
    required this.phone,
    this.dialCode,
    this.firstName,
    this.lastName,
    this.status,
    this.photo,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'],
      phone: json['phone'],
      dialCode: json['dialCode'],
      firstName: json['firstName'],
      lastName: json['lastName'],
      status: json['status'],
      photo: json['photo'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phone': phone,
      'dialCode': dialCode,
      'firstName': firstName,
      'lastName': lastName,
      'status': status,
      'photo': photo,
    };
  }
} 