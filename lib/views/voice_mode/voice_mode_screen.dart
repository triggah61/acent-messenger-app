import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import '../../models/chat_session.dart';
import '../../models/profile.dart';
import '../../services/speech_service.dart';
import '../../services/permission_service.dart';
import '../../constants/config.dart';

class VoiceModeScreen extends StatefulWidget {
  final ChatSession? session;

  const VoiceModeScreen({
    super.key,
    required this.session,
  });

  @override
  State<VoiceModeScreen> createState() => _VoiceModeScreenState();
}

class _VoiceModeScreenState extends State<VoiceModeScreen>
    with TickerProviderStateMixin {
  // Services
  final SpeechService _speechService = SpeechService.instance;
  final PermissionService _permissionService = PermissionService.instance;

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late AnimationController _fadeController;

  // Animations
  late Animation<double> _pulseAnimation;
  late Animation<double> _waveAnimation;
  late Animation<double> _fadeAnimation;

  // State variables
  bool _isListening = false;
  bool _isMuted = false;
  bool _isInitializing = true;
  bool _hasPermission = false;
  String _recognizedText = '';
  String _partialText = '';
  double _soundLevel = 0.0;
  String? _errorMessage;

  // Timers
  Timer? _autoRestartTimer;
  Timer? _displayTimer;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeVoiceMode();
  }

  void _initializeAnimations() {
    // Pulse animation for the microphone icon
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.3,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    // Wave animation for sound visualization
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _waveAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _waveController,
      curve: Curves.easeInOut,
    ));

    // Fade animation for text transitions
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));
  }

  Future<void> _initializeVoiceMode() async {
    try {
      setState(() {
        _isInitializing = true;
        _errorMessage = null;
      });

      // Check microphone permission
      _hasPermission = await _permissionService.requestMicrophonePermission();

      if (!_hasPermission) {
        setState(() {
          _errorMessage = 'Microphone permission is required for voice mode';
          _isInitializing = false;
        });
        return;
      }

      // Initialize speech service
      final initialized = await _speechService.initialize();

      if (!initialized) {
        setState(() {
          _errorMessage = 'Speech recognition is not available on this device';
          _isInitializing = false;
        });
        return;
      }

      // Setup speech service callbacks
      _setupSpeechCallbacks();

      setState(() {
        _isInitializing = false;
      });

      // Start listening automatically
      await _startListening();
    } catch (e) {
      debugPrint('VoiceModeScreen: Error initializing: $e');
      setState(() {
        _errorMessage = 'Failed to initialize voice mode: $e';
        _isInitializing = false;
      });
    }
  }

  void _setupSpeechCallbacks() {
    _speechService.setOnResult((result) {
      debugPrint('VoiceModeScreen: Final result: $result');
      setState(() {
        _recognizedText = result;
        _partialText = '';
      });

      // Show text for a few seconds then fade
      _fadeController.forward();
      _displayTimer?.cancel();
      _displayTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          _fadeController.reverse();
        }
      });
    });

    _speechService.setOnPartialResult((partial) {
      debugPrint('VoiceModeScreen: Partial result: $partial');
      setState(() {
        _partialText = partial;
      });
    });

    _speechService.setOnListeningStateChanged((isListening) {
      debugPrint('VoiceModeScreen: Listening state changed: $isListening');
      setState(() {
        _isListening = isListening;
      });

      if (isListening) {
        _pulseController.repeat(reverse: true);
        _waveController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _waveController.stop();

        // Auto-restart listening if not muted and no error
        if (!_isMuted && _hasPermission && mounted) {
          _autoRestartTimer?.cancel();
          _autoRestartTimer = Timer(const Duration(milliseconds: 500), () {
            if (mounted && !_isMuted) {
              _startListening();
            }
          });
        }
      }
    });

    _speechService.setOnError((error) {
      debugPrint('VoiceModeScreen: Speech error: $error');
      setState(() {
        _errorMessage = error;
      });

      // Clear error after a few seconds
      Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _errorMessage = null;
          });
        }
      });
    });

    _speechService.setOnSoundLevel((level) {
      setState(() {
        _soundLevel = level;
      });
    });
  }

  Future<void> _startListening() async {
    if (_isMuted || !_hasPermission) return;

    try {
      await _speechService.startListening(
        pauseFor: const Duration(seconds: 2),
        listenFor: const Duration(seconds: 30),
      );
    } catch (e) {
      debugPrint('VoiceModeScreen: Error starting listening: $e');
    }
  }

  Future<void> _stopListening() async {
    try {
      await _speechService.stopListening();
    } catch (e) {
      debugPrint('VoiceModeScreen: Error stopping listening: $e');
    }
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });

    // Provide haptic feedback
    HapticFeedback.mediumImpact();

    if (_isMuted) {
      _stopListening();
    } else {
      _startListening();
    }
  }

  void _exitVoiceMode() {
    // Provide haptic feedback
    HapticFeedback.lightImpact();

    // Stop listening and cleanup
    _stopListening();

    // Navigate back to chat
    Navigator.of(context).pop();
  }

  void _showConversationInfo() {
    if (widget.session == null) return;

    if (widget.session!.type == 'group') {
      _showGroupInfoModal();
    } else {
      _showUserInfoModal();
    }
  }

  void _showUserInfoModal() {
    final otherUser = widget.session?.otherUser;
    if (otherUser == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => UserInfoModal(user: otherUser),
    );
  }

  void _showGroupInfoModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GroupInfoModal(session: widget.session!),
    );
  }

  String _getSessionInitials(String? title) {
    if (title == null || title.trim().isEmpty) {
      return '?';
    }

    // Split by spaces and filter out empty strings
    final words =
        title.trim().split(' ').where((word) => word.isNotEmpty).toList();

    if (words.isEmpty) {
      return '?';
    } else if (words.length == 1) {
      return words[0].isNotEmpty ? words[0][0].toUpperCase() : '?';
    } else {
      // Take first letter of first two words
      String first = words[0].isNotEmpty ? words[0][0].toUpperCase() : '';
      String second = words[1].isNotEmpty ? words[1][0].toUpperCase() : '';
      return '$first$second';
    }
  }

  @override
  void dispose() {
    _autoRestartTimer?.cancel();
    _displayTimer?.cancel();
    _pulseController.dispose();
    _waveController.dispose();
    _fadeController.dispose();
    _speechService.clearCallbacks();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF16213E),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: _exitVoiceMode,
      ),
      title: GestureDetector(
        onTap: _showConversationInfo,
        child: Row(
          children: [
            CircleAvatar(
              backgroundImage: widget.session?.photo != null
                  ? NetworkImage(Config.getPhotoUrl(widget.session!.photo!))
                  : null,
              child: widget.session?.photo == null
                  ? Text(
                      _getSessionInitials(widget.session?.title),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.session?.title ?? 'Voice Mode',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.session?.type == 'group')
                    Text(
                      '${widget.session?.recipients.length ?? 0} participants • Voice Mode',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    )
                  else
                    Text(
                      '${widget.session?.otherUser?.dialCode ?? ''} ${widget.session?.otherUser?.phone ?? ''} • Voice Mode',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.7),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      centerTitle: false,
    );
  }

  Widget _buildBody() {
    if (_isInitializing) {
      return _buildLoadingState();
    }

    if (!_hasPermission) {
      return _buildPermissionDeniedState();
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
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
      child: Column(
        children: [
          Expanded(
            child: _buildMainContent(),
          ),
          _buildBottomControls(),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00D4AA)),
          ),
          SizedBox(height: 16),
          Text(
            'Initializing Voice Mode...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionDeniedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.mic_off,
              size: 80,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 24),
            const Text(
              'Microphone Permission Required',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Voice mode needs microphone access to listen to your voice. Please grant permission in settings.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () async {
                await _permissionService.openSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D4AA),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Status indicator
        _buildStatusIndicator(),

        const SizedBox(height: 60),

        // Main microphone visualization
        _buildMicrophoneVisualization(),

        const SizedBox(height: 60),

        // Text display area
        _buildTextDisplay(),

        // Error message
        if (_errorMessage != null) _buildErrorMessage(),
      ],
    );
  }

  Widget _buildStatusIndicator() {
    String status;
    Color color;

    if (_isMuted) {
      status = 'Muted';
      color = Colors.redAccent;
    } else if (_isListening) {
      status = 'Listening...';
      color = const Color(0xFF00D4AA);
    } else {
      status = 'Ready';
      color = Colors.orange;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildMicrophoneVisualization() {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnimation, _waveAnimation]),
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer wave rings
            if (_isListening && !_isMuted) ...[
              _buildWaveRing(100 + (_soundLevel * 50), 0.1),
              _buildWaveRing(130 + (_soundLevel * 70), 0.05),
              _buildWaveRing(160 + (_soundLevel * 90), 0.03),
            ],

            // Main microphone button
            Transform.scale(
              scale: _isListening && !_isMuted ? _pulseAnimation.value : 1.0,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _isMuted
                        ? [Colors.redAccent, Colors.red.shade800]
                        : _isListening
                            ? [const Color(0xFF00D4AA), const Color(0xFF00B894)]
                            : [Colors.grey.shade600, Colors.grey.shade800],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (_isMuted
                              ? Colors.redAccent
                              : const Color(0xFF00D4AA))
                          .withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Icon(
                  _isMuted ? Icons.mic_off : Icons.mic,
                  size: 50,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWaveRing(double size, double opacity) {
    return AnimatedBuilder(
      animation: _waveAnimation,
      builder: (context, child) {
        return Container(
          width: size * (0.8 + (0.4 * _waveAnimation.value)),
          height: size * (0.8 + (0.4 * _waveAnimation.value)),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF00D4AA).withOpacity(
                opacity * (1.0 - _waveAnimation.value),
              ),
              width: 2,
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextDisplay() {
    final displayText =
        _partialText.isNotEmpty ? _partialText : _recognizedText;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          // Real-time text display
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: displayText.isNotEmpty ? 120 : 60,
            child: Center(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Text(
                  displayText.isNotEmpty ? displayText : 'Start speaking...',
                  style: TextStyle(
                    color: displayText.isNotEmpty
                        ? Colors.white
                        : Colors.white.withOpacity(0.5),
                    fontSize: displayText.isNotEmpty ? 18 : 16,
                    fontWeight: displayText.isNotEmpty
                        ? FontWeight.w500
                        : FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),

          // Partial text indicator
          if (_partialText.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Processing...',
                style: TextStyle(
                  color: Colors.orange,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.redAccent, width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _errorMessage!,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Mute/Unmute button
          _buildControlButton(
            icon: _isMuted ? Icons.mic_off : Icons.mic,
            label: _isMuted ? 'Unmute' : 'Mute',
            color: _isMuted ? Colors.redAccent : const Color(0xFF00D4AA),
            onPressed: _toggleMute,
          ),

          // Exit voice mode button
          _buildControlButton(
            icon: Icons.keyboard,
            label: 'Text Chat',
            color: Colors.blueAccent,
            onPressed: _exitVoiceMode,
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color,
                  color.withOpacity(0.7),
                ],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              icon,
              size: 30,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// User Information Modal for Personal Chats
class UserInfoModal extends StatelessWidget {
  final Profile user;

  const UserInfoModal({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),

            // User Avatar
            Stack(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundImage: user.photo != null
                      ? NetworkImage(Config.getPhotoUrl(user.photo!))
                      : null,
                  child: user.photo == null
                      ? Text(
                          _getUserInitials(user),
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // User Name
            Text(
              user.firstName != null && user.lastName != null
                  ? '${user.firstName ?? ''} ${user.lastName ?? ''}'.trim()
                  : user.username ?? 'Unknown User',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            // User Status
            if (user.status != null)
              Text(
                user.status!,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),

            const SizedBox(height: 24),

            // User Information Cards
            _buildInfoCard(
              icon: Icons.phone,
              title: 'Phone',
              value: '${user.dialCode ?? ''} ${user.phone}'.trim(),
            ),

            if (user.username != null)
              _buildInfoCard(
                icon: Icons.alternate_email,
                title: 'Username',
                value: user.username!,
              ),

            if (user.gender != null)
              _buildInfoCard(
                icon: Icons.person,
                title: 'Gender',
                value: user.gender!.toUpperCase(),
              ),

            if (user.dob != null)
              _buildInfoCard(
                icon: Icons.cake,
                title: 'Date of Birth',
                value: _formatDate(user.dob!),
              ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getUserInitials(Profile user) {
    final firstName = user.firstName ?? '';
    final lastName = user.lastName ?? '';

    if (firstName.isNotEmpty && lastName.isNotEmpty) {
      return '${firstName[0]}${lastName[0]}'.toUpperCase();
    } else if (firstName.isNotEmpty) {
      return firstName[0].toUpperCase();
    } else if (user.username != null && user.username!.isNotEmpty) {
      return user.username![0].toUpperCase();
    }
    return '?';
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }
}

/// Group Information Modal for Group Chats
class GroupInfoModal extends StatelessWidget {
  final ChatSession session;

  const GroupInfoModal({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),

            // Group Avatar
            CircleAvatar(
              radius: 50,
              backgroundImage: session.photo != null
                  ? NetworkImage(Config.getPhotoUrl(session.photo!))
                  : null,
              child: session.photo == null
                  ? Text(
                      _getGroupInitials(session.title),
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold),
                    )
                  : null,
            ),

            const SizedBox(height: 16),

            // Group Name
            Text(
              session.title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            // Group Description
            Text(
              '${session.recipients.length} participants',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // Group Info Cards
            _buildGroupInfoCard(
              icon: Icons.group,
              title: 'Participants',
              value: '${session.recipients.length} members',
            ),

            _buildGroupInfoCard(
              icon: Icons.calendar_today,
              title: 'Created',
              value: _formatCreatedDate(session.createdAt),
            ),

            const SizedBox(height: 24),

            // Participants List
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Participants',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...session.recipients.map((recipient) {
                    return _buildParticipantTile(recipient);
                  }).toList(),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupInfoCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantTile(dynamic recipient) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundImage: recipient.user?.photo != null
                ? NetworkImage(Config.getPhotoUrl(recipient.user!.photo!))
                : null,
            child: recipient.user?.photo == null
                ? Text(
                    _getParticipantInitials(recipient.user),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${recipient.user?.firstName ?? ''} ${recipient.user?.lastName ?? ''}'
                      .trim(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (recipient.user?.phone != null)
                  Text(
                    '${recipient.user?.dialCode ?? ''} ${recipient.user?.phone ?? ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
          if (recipient.role == 'admin')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Admin',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.blue[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _getGroupInitials(String title) {
    if (title.trim().isEmpty) return '?';

    final words =
        title.trim().split(' ').where((word) => word.isNotEmpty).toList();

    if (words.isEmpty) {
      return '?';
    } else if (words.length == 1) {
      return words[0].isNotEmpty ? words[0][0].toUpperCase() : '?';
    } else {
      String first = words[0].isNotEmpty ? words[0][0].toUpperCase() : '';
      String second = words[1].isNotEmpty ? words[1][0].toUpperCase() : '';
      return '$first$second';
    }
  }

  String _getParticipantInitials(dynamic user) {
    final firstName = user?.firstName ?? '';
    final lastName = user?.lastName ?? '';

    if (firstName.isNotEmpty && lastName.isNotEmpty) {
      return '${firstName[0]}${lastName[0]}'.toUpperCase();
    } else if (firstName.isNotEmpty) {
      return firstName[0].toUpperCase();
    }
    return '?';
  }

  String _formatCreatedDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
