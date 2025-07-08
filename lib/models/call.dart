/**
 * Call model for representing call sessions
 */
class Call {
  final String id;
  final String channelName;
  final String type; // 'voice' or 'video'
  final String mode; // 'individual' or 'group'
  final CallParticipant initiator;
  final List<CallParticipant> participants;
  final String
      status; // 'initiated', 'ringing', 'active', 'ended', 'missed', 'declined'
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int duration; // Duration in seconds
  final String? endReason;
  final String? chatSessionId;
  final CallQuality? quality;
  final DateTime createdAt;
  final DateTime updatedAt;

  Call({
    required this.id,
    required this.channelName,
    required this.type,
    required this.mode,
    required this.initiator,
    required this.participants,
    required this.status,
    this.startedAt,
    this.endedAt,
    required this.duration,
    this.endReason,
    this.chatSessionId,
    this.quality,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Call.fromJson(Map<String, dynamic> json) {
    return Call(
      id: json['_id'] ?? '',
      channelName: json['channelName'] ?? '',
      type: json['type'] ?? 'voice',
      mode: json['mode'] ?? 'individual',
      // Fix: initiator is a user object directly, not a participant
      initiator: CallParticipant(
        user: CallUser.fromJson(json['initiator'] ?? {}),
        role: 'caller',
        status: 'accepted',
        duration: 0,
      ),
      participants: (json['participants'] as List<dynamic>? ?? [])
          .map((p) => CallParticipant.fromJson(p))
          .toList(),
      status: json['status'] ?? 'initiated',
      startedAt:
          json['startedAt'] != null ? DateTime.parse(json['startedAt']) : null,
      endedAt: json['endedAt'] != null ? DateTime.parse(json['endedAt']) : null,
      duration: json['duration'] ?? 0,
      endReason: json['endReason'],
      // Fix: handle chatSession as object and extract ID
      chatSessionId: json['chatSessionId'] ??
          (json['chatSession'] is Map<String, dynamic>
              ? json['chatSession']['_id']
              : json['chatSession']),
      quality: json['quality'] != null
          ? CallQuality.fromJson(json['quality'])
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'channelName': channelName,
      'type': type,
      'mode': mode,
      'initiator': initiator.toJson(),
      'participants': participants.map((p) => p.toJson()).toList(),
      'status': status,
      'startedAt': startedAt?.toIso8601String(),
      'endedAt': endedAt?.toIso8601String(),
      'duration': duration,
      'endReason': endReason,
      'chatSession': chatSessionId,
      'quality': quality?.toJson(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  // Helper methods
  bool get isActive => status == 'active';
  bool get isEnded => status == 'ended';
  bool get isVoiceCall => type == 'voice';
  bool get isVideoCall => type == 'video';
  bool get isGroupCall => mode == 'group';

  String get formattedDuration {
    if (duration == 0) return '00:00';
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  CallParticipant? getParticipant(String userId) {
    return participants.firstWhere(
      (p) => p.user.id == userId,
      orElse: () => participants.first,
    );
  }

  List<CallParticipant> get activeParticipants {
    return participants.where((p) => p.status == 'accepted').toList();
  }
}

/**
 * Call participant model
 */
class CallParticipant {
  final CallUser user;
  final String role; // 'caller' or 'callee'
  final String
      status; // 'invited', 'ringing', 'accepted', 'declined', 'missed', 'ended'
  final DateTime? joinedAt;
  final DateTime? leftAt;
  final int duration; // Duration in seconds

  CallParticipant({
    required this.user,
    required this.role,
    required this.status,
    this.joinedAt,
    this.leftAt,
    required this.duration,
  });

  factory CallParticipant.fromJson(Map<String, dynamic> json) {
    return CallParticipant(
      user: CallUser.fromJson(json['user'] ?? {}),
      role: json['role'] ?? 'callee',
      status: json['status'] ?? 'invited',
      joinedAt:
          json['joinedAt'] != null ? DateTime.parse(json['joinedAt']) : null,
      leftAt: json['leftAt'] != null ? DateTime.parse(json['leftAt']) : null,
      duration: json['duration'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user': user.toJson(),
      'role': role,
      'status': status,
      'joinedAt': joinedAt?.toIso8601String(),
      'leftAt': leftAt?.toIso8601String(),
      'duration': duration,
    };
  }

  bool get isActive => status == 'accepted';
  bool get isCaller => role == 'caller';
}

/**
 * Call user model (simplified user info for calls)
 */
class CallUser {
  final String id;
  final String firstName;
  final String lastName;
  final String? photo;
  final String? dialCode;
  final String? phone;

  CallUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.photo,
    this.dialCode,
    this.phone,
  });

  factory CallUser.fromJson(Map<String, dynamic> json) {
    return CallUser(
      id: json['_id'] ?? '',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      photo: json['photo'],
      dialCode: json['dialCode'],
      phone: json['phone'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'firstName': firstName,
      'lastName': lastName,
      'photo': photo,
      'dialCode': dialCode,
      'phone': phone,
    };
  }

  String get fullName => '$firstName $lastName'.trim();
  String get displayName => fullName.isNotEmpty ? fullName : 'Unknown User';
}

/**
 * Call quality model
 */
class CallQuality {
  final double? averageRating;
  final String? networkQuality;
  final List<String> issues;

  CallQuality({this.averageRating, this.networkQuality, required this.issues});

  factory CallQuality.fromJson(Map<String, dynamic> json) {
    return CallQuality(
      averageRating: json['averageRating']?.toDouble(),
      networkQuality: json['networkQuality'],
      issues: List<String>.from(json['issues'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'averageRating': averageRating,
      'networkQuality': networkQuality,
      'issues': issues,
    };
  }
}

/**
 * Agora token response model
 */
class AgoraToken {
  final String token;
  final String channelName;
  final String appId;
  final String userId;
  final int integerUid; // The UID that was used to generate the token
  final int expiresAt;
  final Call call;

  AgoraToken({
    required this.token,
    required this.channelName,
    required this.appId,
    required this.userId,
    required this.integerUid,
    required this.expiresAt,
    required this.call,
  });

  factory AgoraToken.fromJson(Map<String, dynamic> json) {
    return AgoraToken(
      token: json['token'] ?? '',
      channelName: json['channelName'] ?? '',
      appId: json['appId'] ?? '',
      userId: json['userId'] ?? '',
      integerUid: json['integerUid'] ?? 0,
      expiresAt: json['expiresAt'] ?? 0,
      call: Call.fromJson(json['call'] ?? {}),
    );
  }

  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch > (expiresAt * 1000);
}
