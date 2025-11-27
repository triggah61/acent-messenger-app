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
  final String? language;
  final Map<String, dynamic>? balance;
  final Map<String, dynamic>? subscription;

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
    this.language,
    this.balance,
    this.subscription,
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
      language: json['language'],
      balance: json['balance'] != null ? Map<String, dynamic>.from(json['balance']) : null,
      subscription: json['subscription'] != null ? Map<String, dynamic>.from(json['subscription']) : null,
    );
  }

  /// Get total credit balance
  double get totalBalance {
    if (balance == null) return 0.0;
    return (balance!['totalBalance'] as num?)?.toDouble() ?? 0.0;
  }

  /// Get top-up balance
  double get topUpBalance {
    if (balance == null) return 0.0;
    return (balance!['topUpBalance'] as num?)?.toDouble() ?? 0.0;
  }

  /// Get subscription balance
  double get subscriptionBalance {
    if (balance == null) return 0.0;
    return (balance!['subscriptionBalance'] as num?)?.toDouble() ?? 0.0;
  }

  /// Get current subscription plan ID
  String? get currentPlanId {
    if (subscription == null || subscription!['currentPlan'] == null) return null;
    return subscription!['currentPlan']['_id']?.toString();
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
      'language': language,
      'balance': balance,
      'subscription': subscription,
    };
  }
}
