class Profile {
  final String id;
  final String phone;
  final String? dialCode;
  final String? firstName;
  final String? lastName;
  final String? username;
  final String? status;
  final String? photo;
  final String? gender;
  final String? dob;

  Profile({
    required this.id,
    required this.phone,
    this.dialCode,
    this.firstName,
    this.lastName,
    this.username,
    this.status,
    this.photo,
    this.gender,
    this.dob,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['_id'] ?? '',
      phone: json['phone'] ?? '',
      dialCode: json['dialCode'],
      firstName: json['firstName'],
      lastName: json['lastName'],
      username: json['username'],
      status: json['status'],
      photo: json['photo'],
      gender: json['gender'],
      dob: json['dob'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phone': phone,
      'dialCode': dialCode,
      'firstName': firstName,
      'lastName': lastName,
      'username': username,
      'status': status,
      'photo': photo,
      'gender': gender,
      'dob': dob,
    };
  }
}
