import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import '../../models/call.dart';
import '../../services/call_service.dart';
import '../../services/auth_service.dart';
import '../../services/pusher_service.dart';
import '../../services/fcm_service.dart';
import '../../services/call_ringtone_service.dart';
import '../../constants/config.dart';
import 'agora_call_screen.dart';

class IncomingCallScreen extends StatefulWidget {
  final Call call;
  final Map<String, dynamic>? notificationData;

  const IncomingCallScreen({
    super.key,
    required this.call,
    this.notificationData,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with TickerProviderStateMixin {
  late final CallService _callService;
  late final PusherService _pusherService;
  late final FCMService _fcmService;
  late AnimationController _pulseController;
  late AnimationController _slideController;
  late Animation<double> _pulseAnimation;
  late Animation<Offset> _slideAnimation;

  Timer? _timeoutTimer;
  bool _isProcessing = false;
  String _callerName = '';
  String _callerPhone = '';
  String? _callerPhotoUrl;

  // Event listeners
  Function(dynamic)? _callDeclinedListener;
  Function(dynamic)? _callEndedListener;

  @override
  void initState() {
    super.initState();
    _callService = CallService(AuthService());
    _pusherService = PusherService.instance;
    _fcmService = FCMService.instance;
    _setupAnimations();
    _loadCallerInfo();
    _startCallTimeout();
    _setupRealtimeEventListeners();

    // Make the screen appear over lock screen
    _setupSystemUI();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _pulseController.dispose();
    _slideController.dispose();
    _cleanupRealtimeEventListeners();

    // Stop ringtone when screen is disposed - use both services for reliability
    _fcmService.stopCallRingtone();
    CallRingtoneService.instance.stopRingtone();

    super.dispose();
  }

  void _setupAnimations() {
    // Pulse animation for avatar
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    _pulseController.repeat(reverse: true);

    // Slide animation for call info
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutBack,
    ));
    _slideController.forward();
  }

  void _setupSystemUI() {
    // Configure system UI for incoming call
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  }

  void _loadCallerInfo() {
    try {
      // Get caller information from the call data
      final caller = widget.call.initiator.user;
      setState(() {
        _callerName = '${caller.firstName} ${caller.lastName}'.trim();
        if (_callerName.isEmpty) {
          _callerName = 'Unknown Caller';
        }
        _callerPhone = '${caller.dialCode ?? ''} ${caller.phone ?? ''}'.trim();
        if (caller.photo != null) {
          _callerPhotoUrl = Config.getPhotoUrl(caller.photo!);
        }
      });
    } catch (e) {
      print('IncomingCallScreen: Error loading caller info: $e');
      setState(() {
        _callerName = 'Unknown Caller';
        _callerPhone = '';
      });
    }
  }

  void _startCallTimeout() {
    // Auto-decline call after 30 seconds with proper cleanup
    _timeoutTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && !_isProcessing) {
        debugPrint('IncomingCallScreen: Call timed out after 30 seconds');
        _handleCallTimeout();
      }
    });
  }

  void _handleCallTimeout() async {
    if (_isProcessing || !mounted) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // Stop ringtone immediately - use both services for reliability
      await _fcmService.stopCallRingtone();
      await CallRingtoneService.instance.stopRingtone();

      // End the call on backend with timeout reason
      await _callService.endCall(widget.call.id, reason: 'timeout');

      // Show timeout message
      _showCallEndedMessage('Call timed out');

      // Close screen
      _closeScreen();
    } catch (e) {
      debugPrint('IncomingCallScreen: Error handling timeout: $e');
      // Still close the screen even if backend call fails
      _closeScreen();
    }
  }

  void _setupRealtimeEventListeners() {
    try {
      // Listen for call declined events
      _callDeclinedListener = (data) {
        debugPrint('IncomingCallScreen: Received call_declined event: $data');

        final callId = data['callId'] as String?;
        if (callId == widget.call.id && mounted) {
          _handleCallDeclined(data);
        }
      };
      _pusherService.addEventListener('call_declined', _callDeclinedListener!);

      // Listen for call ended events
      _callEndedListener = (data) {
        debugPrint('IncomingCallScreen: Received call_ended event: $data');

        final callId = data['callId'] as String?;
        if (callId == widget.call.id && mounted) {
          _handleCallEnded(data);
        }
      };
      _pusherService.addEventListener('call_ended', _callEndedListener!);

      debugPrint(
          'IncomingCallScreen: Set up real-time event listeners for call ${widget.call.id}');
    } catch (e) {
      debugPrint('IncomingCallScreen: Error setting up event listeners: $e');
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
      debugPrint('IncomingCallScreen: Cleaned up real-time event listeners');
    } catch (e) {
      debugPrint('IncomingCallScreen: Error cleaning up event listeners: $e');
    }
  }

  void _handleCallDeclined(Map<String, dynamic> data) {
    if (!mounted || _isProcessing) return;

    final declinedBy = data['declinedBy'] as String?;
    final status = data['status'] as String?;

    debugPrint(
        'IncomingCallScreen: Call declined by $declinedBy, status: $status');

    // Stop ringtone when call is declined by another party
    _fcmService.stopCallRingtone();
    CallRingtoneService.instance.stopRingtone();

    // If all participants have declined or call is fully declined, close the screen
    if (status == 'declined') {
      _showCallEndedMessage('Call declined');
      _closeScreen();
    }
  }

  void _handleCallEnded(Map<String, dynamic> data) {
    if (!mounted || _isProcessing) return;

    final endedBy = data['endedBy'] as String?;
    final reason = data['reason'] as String?;

    debugPrint('IncomingCallScreen: Call ended by $endedBy, reason: $reason');

    // Stop ringtone when call is ended by another party
    _fcmService.stopCallRingtone();
    CallRingtoneService.instance.stopRingtone();

    String message = 'Call ended';
    if (reason == 'timeout') {
      message = 'Call timed out';
    } else if (reason == 'declined') {
      message = 'Call declined';
    }

    _showCallEndedMessage(message);
    _closeScreen();
  }

  void _showCallEndedMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.red.withOpacity(0.8),
      ),
    );
  }

  void _closeScreen() {
    if (!mounted) return;

    // Cancel timeout timer
    _timeoutTimer?.cancel();

    // Close the screen
    Navigator.of(context).pop();
  }

  Future<void> _acceptCall() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // Stop the ringtone immediately - use both services for reliability
      await _fcmService.stopCallRingtone();
      await CallRingtoneService.instance.stopRingtone();

      // Vibrate to provide haptic feedback
      HapticFeedback.mediumImpact();

      // Accept the call on the backend
      final result = await _callService.acceptCall(widget.call.id);

      if (result['success'] == true) {
        // Get Agora token for the call
        final agoraToken = await _callService.getCallToken(widget.call.id);

        if (agoraToken != null) {
          // Navigate to the call screen
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => AgoraCallScreen(
                  call: widget.call,
                  channelName: widget.call.channelName,
                  agoraToken: agoraToken.token,
                  agoraUid: agoraToken.integerUid,
                  isIncoming: true,
                ),
              ),
            );
          }
        } else {
          throw Exception('Failed to get call token');
        }
      } else {
        throw Exception(result['error'] ?? 'Failed to accept call');
      }
    } catch (e) {
      print('IncomingCallScreen: Error accepting call: $e');
      _showErrorAndExit('Failed to accept call: ${e.toString()}');
    }
  }

  Future<void> _declineCall({String reason = 'declined'}) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // Stop the ringtone immediately - use both services for reliability
      await _fcmService.stopCallRingtone();
      await CallRingtoneService.instance.stopRingtone();

      // Vibrate to provide haptic feedback
      HapticFeedback.lightImpact();

      // Decline the call on the backend
      final result = await _callService.declineCall(widget.call.id);

      if (result['success'] == true) {
        // Close the incoming call screen
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        throw Exception(result['error'] ?? 'Failed to decline call');
      }
    } catch (e) {
      print('IncomingCallScreen: Error declining call: $e');
      // Even if decline fails, close the screen
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _showErrorAndExit(String message) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Call Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Close incoming call screen
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
        // Prevent back button, require explicit action
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF1A1A2E),
                Color(0xFF16213E),
                Color(0xFF0F3460),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Top section with call type info
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        widget.call.type == 'video'
                            ? Icons.videocam
                            : Icons.call,
                        color: Colors.white.withOpacity(0.8),
                        size: 32,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Incoming ${widget.call.type} call',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Caller information
                SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    children: [
                      // Caller avatar with pulse animation
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _pulseAnimation.value,
                            child: Container(
                              width: 160,
                              height: 160,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withOpacity(0.3),
                                    spreadRadius: 4,
                                    blurRadius: 20,
                                    offset: const Offset(0, 0),
                                  ),
                                ],
                              ),
                              child: CircleAvatar(
                                radius: 80,
                                backgroundImage: _callerPhotoUrl != null
                                    ? NetworkImage(_callerPhotoUrl!)
                                    : null,
                                backgroundColor: Colors.white.withOpacity(0.2),
                                child: _callerPhotoUrl == null
                                    ? Icon(
                                        Icons.person,
                                        size: 80,
                                        color: Colors.white.withOpacity(0.8),
                                      )
                                    : null,
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 32),

                      // Caller name
                      Text(
                        _callerName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 8),

                      // Caller phone number
                      if (_callerPhone.isNotEmpty)
                        Text(
                          _callerPhone,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),

                      const SizedBox(height: 16),

                      // Call type indicator
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.call.type == 'video'
                                  ? Icons.videocam
                                  : Icons.call,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              widget.call.type == 'video'
                                  ? 'Video Call'
                                  : 'Voice Call',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Action buttons
                if (_isProcessing)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Decline button
                        _buildActionButton(
                          icon: Icons.call_end,
                          color: Colors.red,
                          onTap: () => _declineCall(),
                          heroTag: 'decline',
                        ),

                        // Quick message button (optional)
                        _buildActionButton(
                          icon: Icons.message,
                          color: Colors.grey[700]!,
                          onTap: () {
                            // TODO: Implement quick message feature
                            _declineCall(reason: 'quick_message');
                          },
                          heroTag: 'message',
                          size: 60,
                        ),

                        // Accept button
                        _buildActionButton(
                          icon: widget.call.type == 'video'
                              ? Icons.videocam
                              : Icons.call,
                          color: Colors.green,
                          onTap: _acceptCall,
                          heroTag: 'accept',
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required String heroTag,
    double size = 70,
  }) {
    return Hero(
      tag: heroTag,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(size / 2),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.4),
                  spreadRadius: 2,
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: size * 0.45,
            ),
          ),
        ),
      ),
    );
  }
}
