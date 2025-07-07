import 'package:flutter/material.dart';

/// Agora configuration constants and enums
class AgoraConfig {
  // These will be set from environment variables or backend
  static const String appId = ''; // Will be fetched from backend

  // Default settings
  static const bool enableAudio = true;
  static const bool enableVideo = true;
  static const bool muteLocalAudio = false;
  static const bool muteLocalVideo = false;

  // Call quality settings
  static const int audioBitrate = 48;
  static const int videoWidth = 640;
  static const int videoHeight = 480;
  static const int videoFrameRate = 15;
  static const int videoBitrate = 400;
}

/// Call state enums
enum CallState {
  idle,
  connecting,
  connected,
  reconnecting,
  disconnected,
  ended,
  failed,
}

/// Call type enum
enum CallType {
  voice,
  video,
}

/// Call mode enum
enum CallMode {
  individual,
  group,
}

/// Call status enum
enum CallStatus {
  initiated,
  ringing,
  answered,
  ended,
  missed,
  declined,
  failed,
}

/// Participant status enum
enum ParticipantStatus {
  invited,
  joined,
  left,
  declined,
}

/// Media control state class
class MediaControlState {
  bool isAudioMuted;
  bool isVideoMuted;
  bool isSpeakerOn;
  bool isCameraFront;

  MediaControlState({
    this.isAudioMuted = false,
    this.isVideoMuted = false,
    this.isSpeakerOn = true,
    this.isCameraFront = true,
  });

  MediaControlState copyWith({
    bool? isAudioMuted,
    bool? isVideoMuted,
    bool? isSpeakerOn,
    bool? isCameraFront,
  }) {
    return MediaControlState(
      isAudioMuted: isAudioMuted ?? this.isAudioMuted,
      isVideoMuted: isVideoMuted ?? this.isVideoMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isCameraFront: isCameraFront ?? this.isCameraFront,
    );
  }
}

/// Call UI configuration
class CallUIConfig {
  static const Duration callTimeout = Duration(seconds: 30);
  static const Duration reconnectTimeout = Duration(seconds: 10);

  // Colors
  static const Color primaryColor = Colors.blue;
  static const Color errorColor = Colors.red;
  static const Color successColor = Colors.green;
  static const Color warningColor = Colors.orange;

  // Button colors
  static const Color endCallColor = Colors.red;
  static const Color muteColor = Colors.grey;
  static const Color unmuteColor = Colors.white;

  // Icon sizes
  static const double smallIconSize = 24.0;
  static const double mediumIconSize = 32.0;
  static const double largeIconSize = 48.0;
}
