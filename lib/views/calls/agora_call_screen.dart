import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:async';

import '../../models/call.dart';
import '../../services/call_service.dart';
import '../../services/auth_service.dart';
import '../../services/permission_service.dart';
import '../../services/pusher_service.dart';
import '../../constants/env_config.dart';

class AgoraCallScreen extends StatefulWidget {
  final Call call;
  final String channelName;
  final String agoraToken;
  final int agoraUid; // Use the exact UID that was used to generate the token
  final bool isIncoming;

  const AgoraCallScreen({
    super.key,
    required this.call,
    required this.channelName,
    required this.agoraToken,
    required this.agoraUid,
    this.isIncoming = false,
  });

  @override
  State<AgoraCallScreen> createState() => _AgoraCallScreenState();
}

class _AgoraCallScreenState extends State<AgoraCallScreen> {
  RtcEngine? _engine;
  late final CallService _callService;
  late final PusherService _pusherService;

  // Call state
  bool _isJoined = false;
  bool _isCallActive = false;
  bool _isConnecting = true;
  String _callStatus = 'Connecting...';

  // Media controls
  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _isSpeakerOn = true;
  bool _isCameraFront = true;

  // UI state
  bool _showControls = true;
  Timer? _hideControlsTimer;

  // Participants
  Set<int> _remoteUsers = {};
  int? _localUserUid;

  // Call timing
  DateTime? _callStartTime;
  Timer? _callTimer;
  String _callDuration = '00:00';

  // Event listeners
  Function(dynamic)? _callDeclinedListener;
  Function(dynamic)? _callEndedListener;

  @override
  void initState() {
    super.initState();
    _callService = CallService(AuthService());
    _pusherService = PusherService.instance;
    _setupWakelock();
    _setupRealtimeEventListeners();
    _initializeAgora();
  }

  @override
  void dispose() {
    _cleanup();
    _cleanupRealtimeEventListeners();
    super.dispose();
  }

  void _setupRealtimeEventListeners() {
    try {
      // Listen for call declined events
      _callDeclinedListener = (data) {
        debugPrint('AgoraCallScreen: Received call_declined event: $data');

        final callId = data['callId'] as String?;
        if (callId == widget.call.id && mounted) {
          _handleCallDeclined(data);
        }
      };
      _pusherService.addEventListener('call_declined', _callDeclinedListener!);

      // Listen for call ended events
      _callEndedListener = (data) {
        debugPrint('AgoraCallScreen: Received call_ended event: $data');

        final callId = data['callId'] as String?;
        if (callId == widget.call.id && mounted) {
          _handleCallEnded(data);
        }
      };
      _pusherService.addEventListener('call_ended', _callEndedListener!);

      debugPrint(
          'AgoraCallScreen: Set up real-time event listeners for call ${widget.call.id}');
    } catch (e) {
      debugPrint('AgoraCallScreen: Error setting up event listeners: $e');
    }
  }

  void _cleanupRealtimeEventListeners() {
    try {
      if (_callDeclinedListener != null) {
        _pusherService.removeEventListener(
            'call_declined', _callDeclinedListener!);
      }
      if (_callEndedListener != null) {
        _pusherService.removeEventListener('call_ended', _callEndedListener!);
      }
      debugPrint('AgoraCallScreen: Cleaned up real-time event listeners');
    } catch (e) {
      debugPrint('AgoraCallScreen: Error cleaning up event listeners: $e');
    }
  }

  void _handleCallDeclined(Map<String, dynamic> data) {
    if (!mounted) return;

    final declinedBy = data['declinedBy'] as String?;
    final status = data['status'] as String?;

    debugPrint(
        'AgoraCallScreen: Call declined by $declinedBy, status: $status');

    // If all participants have declined or call is fully declined, end the call
    if (status == 'declined') {
      _showCallEndedMessage('Call declined by other party');
      _endCallAndClose();
    }
  }

  void _handleCallEnded(Map<String, dynamic> data) {
    if (!mounted) return;

    final endedBy = data['endedBy'] as String?;
    final reason = data['reason'] as String?;

    debugPrint('AgoraCallScreen: Call ended by $endedBy, reason: $reason');

    String message = 'Call ended';
    if (reason == 'timeout') {
      message = 'Call timed out';
    } else if (reason == 'declined') {
      message = 'Call declined';
    } else if (reason == 'normal') {
      message = 'Call ended by other party';
    }

    _showCallEndedMessage(message);
    _endCallAndClose();
  }

  void _showCallEndedMessage(String message) {
    if (!mounted) return;

    // Show a brief message before closing
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.red.withOpacity(0.8),
      ),
    );
  }

  Future<void> _endCallAndClose() async {
    if (!mounted) return;

    try {
      // Clean up Agora and close the screen
      await _cleanup();
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('AgoraCallScreen: Error during call end cleanup: $e');
      Navigator.of(context).pop();
    }
  }

  Future<void> _setupWakelock() async {
    try {
      // Keep screen awake during call
      await WakelockPlus.enable();
      print('AgoraCallScreen: Wakelock enabled successfully');
    } catch (e) {
      print('AgoraCallScreen: Error enabling wakelock: $e');
      // Don't fail the call initialization if wakelock fails
      // This is a non-critical feature
    }
  }

  Future<void> _initializeAgora() async {
    try {
      // Request permissions
      await _requestPermissions();

      // Get Agora App ID from environment configuration
      final appId = EnvConfig.agoraAppId;
      print('AgoraCallScreen: Using App ID: $appId');

      // Validate Agora App ID
      if (appId.isEmpty) {
        throw Exception(
          'Agora App ID not configured. Please add AGORA_APP_ID to your .env file with a valid Agora App ID from https://console.agora.io/',
        );
      }

      // Initialize Agora engine
      _engine = createAgoraRtcEngine();
      if (_engine == null) {
        throw Exception('Failed to create Agora RTC engine');
      }

      await _engine!.initialize(
        RtcEngineContext(
          appId: appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      // Set up event handlers
      _engine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: _onJoinChannelSuccess,
          onUserJoined: _onUserJoined,
          onUserOffline: _onUserOffline,
          onLeaveChannel: _onLeaveChannel,
          onError: _onError,
          onConnectionStateChanged: _onConnectionStateChanged,
          onRemoteVideoStateChanged: _onRemoteVideoStateChanged,
          // onLocalVideoStateChanged: _onLocalVideoStateChanged, // Commented out due to SDK compatibility
        ),
      );

      // Configure audio/video settings
      await _configureMediaSettings();

      // Join channel
      await _joinChannel();
    } catch (e) {
      print('AgoraCallScreen: Error initializing Agora: $e');
      _showErrorAndExit('Failed to initialize call: $e');
    }
  }

  Future<void> _requestPermissions() async {
    final permissionService = PermissionService.instance;

    print(
      'AgoraCallScreen: Checking permissions for ${widget.call.type} call...',
    );

    // Check if permissions were already initialized during app startup
    if (!permissionService.isPermissionsInitialized) {
      print(
        'AgoraCallScreen: Permissions not initialized, initializing now...',
      );
      await permissionService.initializePermissions();
    }

    // Log current permission status
    final detailedStatus =
        await permissionService.getDetailedPermissionStatus();
    print('AgoraCallScreen: Current permission status: $detailedStatus');

    // Check if we have the required permissions for this call type
    if (widget.call.type == 'video') {
      if (!permissionService.canMakeVideoCall()) {
        // Try to request missing permissions one more time
        print('AgoraCallScreen: Video call permissions missing, requesting...');

        if (!permissionService.isMicrophoneGranted) {
          print('AgoraCallScreen: Requesting microphone permission...');
          final micGranted =
              await permissionService.requestMicrophonePermission();
          print('AgoraCallScreen: Microphone permission granted: $micGranted');
          if (!micGranted) {
            throw Exception(
              'Microphone permission is required for video calls.\n\nTo fix this:\n1. Go to your device Settings\n2. Find "Q Messenger" in Apps\n3. Enable Microphone permission\n4. Try calling again',
            );
          }
        }

        if (!permissionService.isCameraGranted) {
          print('AgoraCallScreen: Requesting camera permission...');
          final camGranted = await permissionService.requestCameraPermission();
          print('AgoraCallScreen: Camera permission granted: $camGranted');
          if (!camGranted) {
            throw Exception(
              'Camera permission is required for video calls.\n\nTo fix this:\n1. Go to your device Settings\n2. Find "Q Messenger" in Apps\n3. Enable Camera permission\n4. Try calling again',
            );
          }
        }
      }
    } else {
      // Voice call
      if (!permissionService.canMakeVoiceCall()) {
        print('AgoraCallScreen: Voice call permissions missing, requesting...');
        final micGranted =
            await permissionService.requestMicrophonePermission();
        print('AgoraCallScreen: Microphone permission granted: $micGranted');
        if (!micGranted) {
          throw Exception(
            'Microphone permission is required for voice calls.\n\nTo fix this:\n1. Go to your device Settings\n2. Find "Q Messenger" in Apps\n3. Enable Microphone permission\n4. Try calling again',
          );
        }
      }
    }

    print('AgoraCallScreen: All required permissions granted successfully');
  }

  Future<void> _configureMediaSettings() async {
    if (_engine == null) return;

    // Audio settings
    await _engine!.enableAudio();
    await _engine!.setDefaultAudioRouteToSpeakerphone(_isSpeakerOn);

    // Video settings for video calls
    if (widget.call.type == 'video') {
      await _engine!.enableVideo();
      await _engine!.startPreview();

      // Set video configuration
      await _engine!.setVideoEncoderConfiguration(
        const VideoEncoderConfiguration(
          dimensions: VideoDimensions(width: 640, height: 480),
          frameRate: 15,
          bitrate: 400,
        ),
      );
    }
  }

  Future<void> _joinChannel() async {
    try {
      if (_engine == null) {
        throw Exception('Agora engine not initialized');
      }

      // Get the current user's ID to use as UID
      final uid = await _getUserUid();

      print('AgoraCallScreen: Joining channel with UID: $uid');
      print('AgoraCallScreen: Channel: ${widget.channelName}');
      print('AgoraCallScreen: Token length: ${widget.agoraToken.length}');

      await _engine!.joinChannel(
        token: widget.agoraToken,
        channelId: widget.channelName,
        uid: uid,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      _localUserUid = uid;
    } catch (e) {
      print('AgoraCallScreen: Error joining channel: $e');
      throw Exception('Failed to join call: $e');
    }
  }

  Future<int> _getUserUid() async {
    // Use the exact UID that the backend calculated and used to generate the token
    // This ensures perfect consistency between token generation and channel joining
    final uid = widget.agoraUid;

    print('AgoraCallScreen: Using backend-calculated UID: $uid');
    return uid;
  }

  // Agora Event Handlers
  void _onJoinChannelSuccess(RtcConnection connection, int elapsed) {
    print('AgoraCallScreen: Joined channel successfully');
    setState(() {
      _isJoined = true;
      _isConnecting = false;
      _callStatus = widget.call.type == 'video' ? 'Video Call' : 'Voice Call';
    });

    // Accept the call if it's incoming
    if (widget.isIncoming) {
      _acceptCall();
    }
  }

  void _onUserJoined(RtcConnection connection, int remoteUid, int elapsed) {
    print('AgoraCallScreen: User joined: $remoteUid');
    setState(() {
      _remoteUsers.add(remoteUid);
      if (!_isCallActive) {
        _isCallActive = true;
        _callStatus = 'Connected';
        _startCallTimer();
      }
    });
  }

  void _onUserOffline(
    RtcConnection connection,
    int remoteUid,
    UserOfflineReasonType reason,
  ) {
    print('AgoraCallScreen: User offline: $remoteUid, reason: $reason');
    setState(() {
      _remoteUsers.remove(remoteUid);
      if (_remoteUsers.isEmpty) {
        _callStatus = 'Call ended';
        _endCall();
      }
    });
  }

  void _onLeaveChannel(RtcConnection connection, RtcStats stats) {
    print('AgoraCallScreen: Left channel');
    setState(() {
      _isJoined = false;
      _remoteUsers.clear();
    });
  }

  void _onError(ErrorCodeType err, String msg) {
    print('AgoraCallScreen: Error: $err, message: $msg');
    _showErrorAndExit('Call error: $msg');
  }

  void _onConnectionStateChanged(
    RtcConnection connection,
    ConnectionStateType state,
    ConnectionChangedReasonType reason,
  ) {
    print('AgoraCallScreen: Connection state changed: $state, reason: $reason');

    switch (state) {
      case ConnectionStateType.connectionStateConnecting:
        setState(() {
          _callStatus = 'Connecting...';
          _isConnecting = true;
        });
        break;
      case ConnectionStateType.connectionStateConnected:
        setState(() {
          _callStatus =
              widget.call.type == 'video' ? 'Video Call' : 'Voice Call';
          _isConnecting = false;
        });
        break;
      case ConnectionStateType.connectionStateReconnecting:
        setState(() {
          _callStatus = 'Reconnecting...';
          _isConnecting = true;
        });
        break;
      case ConnectionStateType.connectionStateFailed:
        _showErrorAndExit('Connection failed');
        break;
      default:
        break;
    }
  }

  void _onRemoteVideoStateChanged(
    RtcConnection connection,
    int remoteUid,
    RemoteVideoState state,
    RemoteVideoStateReason reason,
    int elapsed,
  ) {
    print('AgoraCallScreen: Remote video state changed: $state');
  }

  // Local video state change handler commented out due to SDK compatibility issues
  // void _onLocalVideoStateChanged(VideoSourceType source,
  //     LocalVideoStreamState state, LocalVideoStreamReason reason) {
  //   print('AgoraCallScreen: Local video state changed: $state, reason: $reason');
  // }

  // Call management methods
  Future<void> _acceptCall() async {
    try {
      final result = await _callService.acceptCall(widget.call.id);
      if (result['success'] != true) {
        throw Exception(result['error'] ?? 'Failed to accept call');
      }
    } catch (e) {
      print('AgoraCallScreen: Error accepting call: $e');
      _showErrorAndExit('Failed to accept call: $e');
    }
  }

  Future<void> _endCall() async {
    try {
      await _callService.endCall(widget.call.id);
      await _cleanup();
      Navigator.of(context).pop();
    } catch (e) {
      print('AgoraCallScreen: Error ending call: $e');
      Navigator.of(context).pop();
    }
  }

  Future<void> _cleanup() async {
    _callTimer?.cancel();
    _hideControlsTimer?.cancel();

    try {
      if (_engine != null) {
        await _engine!.leaveChannel();
        await _engine!.release();
        _engine = null;
      }
      await WakelockPlus.disable();
    } catch (e) {
      print('AgoraCallScreen: Error during cleanup: $e');
    }
  }

  // Media control methods
  Future<void> _toggleMute() async {
    if (_engine == null) return;

    try {
      await _engine!.muteLocalAudioStream(!_isMuted);
      setState(() {
        _isMuted = !_isMuted;
      });
    } catch (e) {
      print('AgoraCallScreen: Error toggling mute: $e');
    }
  }

  Future<void> _toggleVideo() async {
    if (widget.call.type != 'video' || _engine == null) return;

    try {
      await _engine!.muteLocalVideoStream(!_isVideoOff);
      setState(() {
        _isVideoOff = !_isVideoOff;
      });
    } catch (e) {
      print('AgoraCallScreen: Error toggling video: $e');
    }
  }

  Future<void> _toggleSpeaker() async {
    if (_engine == null) return;

    try {
      await _engine!.setDefaultAudioRouteToSpeakerphone(!_isSpeakerOn);
      setState(() {
        _isSpeakerOn = !_isSpeakerOn;
      });
    } catch (e) {
      print('AgoraCallScreen: Error toggling speaker: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (widget.call.type != 'video' || _engine == null) return;

    try {
      await _engine!.switchCamera();
      setState(() {
        _isCameraFront = !_isCameraFront;
      });
    } catch (e) {
      print('AgoraCallScreen: Error switching camera: $e');
    }
  }

  // Timer methods
  void _startCallTimer() {
    _callStartTime = DateTime.now();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_callStartTime != null) {
        final duration = DateTime.now().difference(_callStartTime!);
        setState(() {
          _callDuration = _formatDuration(duration);
        });
      }
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // UI control methods
  void _toggleControlsVisibility() {
    setState(() {
      _showControls = !_showControls;
    });

    if (_showControls) {
      _startHideControlsTimer();
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _showErrorAndExit(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Call Configuration Error'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              if (message.contains('Agora App ID not configured')) ...[
                const SizedBox(height: 16),
                const Text(
                  'To fix this issue:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('1. Go to https://console.agora.io/'),
                const Text('2. Create a project and get your App ID'),
                const Text(
                  '3. Set AGORA_APP_ID in your backend environment',
                ),
                const Text('4. Set AGORA_APP_CERTIFICATE as well'),
                const Text('5. Restart your backend server'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _endCall();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: widget.call.type == 'video' ? _toggleControlsVisibility : null,
          child: Stack(
            children: [
              // Video content or audio call background
              if (widget.call.type == 'video')
                _buildVideoView()
              else
                _buildAudioCallView(),

              // Call status overlay
              if (_isConnecting || !_isCallActive) _buildStatusOverlay(),

              // Controls overlay
              if (_showControls || widget.call.type == 'voice')
                _buildControlsOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoView() {
    return Stack(
      children: [
        // Remote video (full screen)
        if (_remoteUsers.isNotEmpty && _engine != null)
          AgoraVideoView(
            controller: VideoViewController.remote(
              rtcEngine: _engine!,
              canvas: VideoCanvas(uid: _remoteUsers.first),
              connection: RtcConnection(channelId: widget.channelName),
            ),
          )
        else
          Container(
            color: Colors.black,
            child: const Center(
              child: Text(
                'Waiting for other participant...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),

        // Local video (small overlay)
        if (!_isVideoOff && _engine != null)
          Positioned(
            top: 100,
            right: 20,
            child: SizedBox(
              width: 120,
              height: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AgoraVideoView(
                  controller: VideoViewController(
                    rtcEngine: _engine!,
                    canvas: const VideoCanvas(uid: 0),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAudioCallView() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E3A8A), Color(0xFF1E40AF)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // User avatar
            CircleAvatar(
              radius: 80,
              backgroundColor: Colors.white.withOpacity(0.2),
              child: Icon(
                Icons.person,
                size: 80,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 24),

            // User name
            Text(
              _getOtherParticipantName(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),

            // Call status
            Text(
              _callStatus,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 16,
              ),
            ),

            // Call duration
            if (_isCallActive)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _callDuration,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 14,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            const SizedBox(height: 16),
            Text(
              _callStatus,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return Positioned.fill(
      child: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: _endCall,
                  ),
                  const Spacer(),
                  Text(
                    _callStatus,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  if (_isCallActive)
                    Text(
                      _callDuration,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                ],
              ),
            ),

            const Spacer(),

            // Bottom controls
            Container(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Mute/Unmute
                  _buildControlButton(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    color: _isMuted ? Colors.red : Colors.white,
                    backgroundColor:
                        _isMuted ? Colors.white : Colors.black.withOpacity(0.3),
                    onTap: _toggleMute,
                  ),

                  // Speaker/Earpiece (for voice calls)
                  if (widget.call.type == 'voice')
                    _buildControlButton(
                      icon: _isSpeakerOn ? Icons.volume_up : Icons.hearing,
                      color: Colors.white,
                      backgroundColor: Colors.black.withOpacity(0.3),
                      onTap: _toggleSpeaker,
                    ),

                  // Video toggle (for video calls)
                  if (widget.call.type == 'video')
                    _buildControlButton(
                      icon: _isVideoOff ? Icons.videocam_off : Icons.videocam,
                      color: _isVideoOff ? Colors.red : Colors.white,
                      backgroundColor: _isVideoOff
                          ? Colors.white
                          : Colors.black.withOpacity(0.3),
                      onTap: _toggleVideo,
                    ),

                  // Camera switch (for video calls)
                  if (widget.call.type == 'video')
                    _buildControlButton(
                      icon: Icons.flip_camera_ios,
                      color: Colors.white,
                      backgroundColor: Colors.black.withOpacity(0.3),
                      onTap: _switchCamera,
                    ),

                  // End call
                  _buildControlButton(
                    icon: Icons.call_end,
                    color: Colors.white,
                    backgroundColor: Colors.red,
                    onTap: _endCall,
                    size: 65,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required Color backgroundColor,
    required VoidCallback onTap,
    double size = 55,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              spreadRadius: 1,
              blurRadius: 3,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: color, size: size * 0.5),
      ),
    );
  }

  String _getOtherParticipantName() {
    // Get the name of the other participant
    // This should be implemented based on your app's user data structure
    return 'Participant';
  }
}
