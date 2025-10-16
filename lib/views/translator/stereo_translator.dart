import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';

import '../../services/config_service.dart' as config_service;
import '../../services/permission_service.dart';
import '../../services/bluetooth_service.dart';
import '../../services/audio_channel_service.dart';
import '../../services/channel_audio_player.dart';

class StereoTranslator extends StatefulWidget {
  const StereoTranslator({super.key});

  @override
  State<StereoTranslator> createState() => _StereoTranslatorState();
}

class _StereoTranslatorState extends State<StereoTranslator>
    with TickerProviderStateMixin {
  // Services
  final config_service.ConfigService _configService =
      config_service.ConfigService.instance;
  final PermissionService _permissionService = PermissionService.instance;
  final BluetoothService _bluetoothService = BluetoothService();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioChannelService _audioChannelService = AudioChannelService();
  final ChannelAudioPlayer _leftChannelPlayer = ChannelAudioPlayer();
  final ChannelAudioPlayer _rightChannelPlayer = ChannelAudioPlayer();

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _waveController;

  // Animations
  late Animation<double> _pulseAnimation;
  late Animation<double> _waveAnimation;

  // Languages
  List<config_service.Language> _supportedLanguages = [];

  // Speaker-specific languages (Left and Right earbuds)
  Map<String, config_service.Language> _earbudLanguages = {};

  // Recording state
  bool _isRecording = false;
  bool _isInitialized = false;

  // Bluetooth state
  bool _isBluetoothConnected = false;
  String _connectedDeviceName = 'No device';

  // Recorded audio paths
  String? _leftAudioPath;
  String? _rightAudioPath;

  // Playback state
  bool _isPlayingLeft = false;
  bool _isPlayingRight = false;

  // Colors for earbuds
  final Color _leftEarbudColor = const Color(0xFF2196F3); // Blue
  final Color _rightEarbudColor = const Color(0xFFE91E63); // Pink

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeServices();
  }

  void _initializeAnimations() {
    // Pulse animation for recording button
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Wave animation
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _waveAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _waveController, curve: Curves.linear),
    );
  }

  Future<void> _initializeServices() async {
    try {
      // Request microphone permission
      final hasPermission =
          await _permissionService.requestMicrophonePermission();
      if (!hasPermission) {
        _showError('Microphone permission is required');
        return;
      }

      // Load supported languages
      final configLanguages = await _configService.getSupportedLanguages();
      if (configLanguages.isEmpty) {
        throw Exception('No supported languages found');
      }

      setState(() {
        _supportedLanguages = configLanguages;
        // Set default languages for earbuds
        final defaultEnglish = _supportedLanguages.firstWhere(
          (lang) => lang.code == 'en',
          orElse: () => _supportedLanguages.first,
        );
        _earbudLanguages = {
          'left': defaultEnglish, // Left earbud
          'right': defaultEnglish, // Right earbud
        };
        _isInitialized = true;
      });

      // Check Bluetooth connection
      await _checkBluetoothConnection();

      debugPrint('StereoTranslator: Services initialized successfully');
    } catch (e) {
      debugPrint('StereoTranslator: Initialization error: $e');
      _showError('Failed to initialize translator: $e');
    }
  }

  Future<void> _checkBluetoothConnection() async {
    try {
      debugPrint('StereoTranslator: Checking Bluetooth connection...');

      // Initialize Bluetooth service
      await _bluetoothService.initialize();

      // Check connection
      final deviceInfo = await _bluetoothService.checkConnection();

      debugPrint('StereoTranslator: ${deviceInfo.toString()}');

      setState(() {
        _isBluetoothConnected = deviceInfo.isConnected;
        _connectedDeviceName = deviceInfo.deviceName;
      });

      // Show popup if not connected
      if (!_isBluetoothConnected && mounted) {
        _showBluetoothPrompt();
      }
    } catch (e) {
      debugPrint('StereoTranslator: Error checking Bluetooth: $e');
      setState(() {
        _isBluetoothConnected = false;
        _connectedDeviceName = 'Error checking device';
      });
    }
  }

  void _showBluetoothPrompt() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1D1E33),
          title: const Row(
            children: [
              Icon(Icons.bluetooth_disabled, color: Colors.red, size: 30),
              SizedBox(width: 12),
              Text(
                'Bluetooth Required',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
          content: const Text(
            'Please connect a stereo Bluetooth headset to use this feature.\n\n'
            'Make sure your Bluetooth headset supports stereo audio (left and right channels).',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _checkBluetoothConnection();
              },
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('Check Connection'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D9FF),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      if (!_isBluetoothConnected) {
        _showBluetoothPrompt();
        return;
      }

      if (await _audioRecorder.hasPermission()) {
        // Generate file paths for left and right channels
        final Directory appDir = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        _leftAudioPath = '${appDir.path}/left_channel_$timestamp.wav';
        _rightAudioPath = '${appDir.path}/right_channel_$timestamp.wav';

        debugPrint('StereoTranslator: Recording to: $_leftAudioPath');

        // Start recording (stereo)
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 44100, // Higher sample rate for stereo
            numChannels: 2, // Stereo recording
          ),
          path: _leftAudioPath!,
        );

        setState(() {
          _isRecording = true;
        });

        _pulseController.repeat(reverse: true);
        _waveController.repeat();

        debugPrint('StereoTranslator: Stereo recording started');
      } else {
        _showError('Microphone permission denied');
      }
    } catch (e) {
      debugPrint('StereoTranslator: Error starting recording: $e');
      _showError('Failed to start recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      // Stop recording
      final String? audioPath = await _audioRecorder.stop();

      setState(() {
        _isRecording = false;
      });

      _pulseController.stop();
      _pulseController.reset();
      _waveController.stop();

      if (audioPath != null) {
        debugPrint('StereoTranslator: Recording stopped');
        // TODO: Split stereo audio into left and right channels
        await _processStereoAudio(audioPath);
      } else {
        _showError('No audio recorded');
      }
    } catch (e) {
      debugPrint('StereoTranslator: Error stopping recording: $e');
      _showError('Failed to stop recording: $e');
    }
  }

  Future<void> _processStereoAudio(String stereoAudioPath) async {
    try {
      debugPrint('StereoTranslator: Processing stereo audio: $stereoAudioPath');

      // Show processing indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Separating stereo channels...'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Separate stereo channels using AudioChannelService
      final channelFiles =
          await _audioChannelService.separateStereoChannels(stereoAudioPath);

      if (channelFiles != null) {
        setState(() {
          _leftAudioPath = channelFiles.leftChannelPath;
          _rightAudioPath = channelFiles.rightChannelPath;
        });

        debugPrint('StereoTranslator: Channels separated successfully');
        debugPrint('Left: $_leftAudioPath');
        debugPrint('Right: $_rightAudioPath');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  '✓ Channels separated! You can now play each earbud separately.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }

        // Clean up the original stereo file
        try {
          await File(stereoAudioPath).delete();
          debugPrint('StereoTranslator: Cleaned up stereo file');
        } catch (e) {
          debugPrint('StereoTranslator: Failed to delete stereo file: $e');
        }
      } else {
        _showError('Failed to separate audio channels');
      }
    } catch (e) {
      debugPrint('StereoTranslator: Error processing stereo audio: $e');
      _showError('Failed to process audio: $e');
    }
  }

  Future<void> _playLeftChannel() async {
    if (_leftAudioPath == null) {
      _showError('No left channel audio recorded');
      return;
    }

    try {
      if (_isPlayingLeft) {
        await _leftChannelPlayer.stop();
        setState(() {
          _isPlayingLeft = false;
        });
        debugPrint('StereoTranslator: Stopped left channel playback');
      } else {
        // Play on LEFT channel only (balance = -1.0)
        await _leftChannelPlayer.playOnChannel(
            _leftAudioPath!, AudioChannel.left);
        setState(() {
          _isPlayingLeft = true;
        });
        debugPrint(
            'StereoTranslator: Playing left channel on LEFT earbud only');

        // Listen for completion
        _leftChannelPlayer.onPlayerComplete.listen((_) {
          if (mounted) {
            setState(() {
              _isPlayingLeft = false;
            });
          }
        });
      }
    } catch (e) {
      debugPrint('StereoTranslator: Error playing left channel: $e');
      _showError('Failed to play left channel: $e');
    }
  }

  Future<void> _playRightChannel() async {
    if (_rightAudioPath == null) {
      _showError('No right channel audio recorded');
      return;
    }

    try {
      if (_isPlayingRight) {
        await _rightChannelPlayer.stop();
        setState(() {
          _isPlayingRight = false;
        });
        debugPrint('StereoTranslator: Stopped right channel playback');
      } else {
        // Play on RIGHT channel only (balance = 1.0)
        await _rightChannelPlayer.playOnChannel(
            _rightAudioPath!, AudioChannel.right);
        setState(() {
          _isPlayingRight = true;
        });
        debugPrint(
            'StereoTranslator: Playing right channel on RIGHT earbud only');

        // Listen for completion
        _rightChannelPlayer.onPlayerComplete.listen((_) {
          if (mounted) {
            setState(() {
              _isPlayingRight = false;
            });
          }
        });
      }
    } catch (e) {
      debugPrint('StereoTranslator: Error playing right channel: $e');
      _showError('Failed to play right channel: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  Widget _buildTestScreen() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth Debug'),
        backgroundColor: const Color(0xFF1D1E33),
      ),
      backgroundColor: const Color(0xFF0A0E21),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isBluetoothConnected
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth_disabled,
                size: 100,
                color: _isBluetoothConnected ? Colors.green : Colors.red,
              ),
              const SizedBox(height: 20),
              Text(
                'Status: ${_isBluetoothConnected ? "Connected" : "Not Connected"}',
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 10),
              Text(
                'Device: $_connectedDeviceName',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                onPressed: () async {
                  await _checkBluetoothConnection();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Recheck Connection'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D9FF),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    _audioRecorder.dispose();
    _leftChannelPlayer.dispose();
    _rightChannelPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E21),
        appBar: AppBar(
          title: const Text('Stereo Translator'),
          backgroundColor: const Color(0xFF1D1E33),
        ),
        body: const Center(
          child: CircularProgressIndicator(
            color: Color(0xFF00D9FF),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        title: const Text('Stereo Translator'),
        backgroundColor: const Color(0xFF1D1E33),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => _buildTestScreen(),
                ),
              );
            },
            tooltip: 'Test Bluetooth',
          ),
          IconButton(
            icon: const Icon(Icons.bluetooth),
            onPressed: _checkBluetoothConnection,
            tooltip: 'Check Bluetooth',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Bluetooth Status
                _buildBluetoothStatus(),
                const SizedBox(height: 24),

                // Earbud Configuration
                _buildEarbudConfiguration(),
                const SizedBox(height: 32),

                // Recording Button
                _buildRecordingButton(),
                const SizedBox(height: 32),

                // Playback Controls
                if (_leftAudioPath != null && _rightAudioPath != null)
                  _buildPlaybackControls(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBluetoothStatus() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isBluetoothConnected ? Colors.green : Colors.red,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isBluetoothConnected
                ? Icons.bluetooth_connected
                : Icons.bluetooth_disabled,
            color: _isBluetoothConnected ? Colors.green : Colors.red,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isBluetoothConnected ? 'Connected' : 'Not Connected',
                  style: TextStyle(
                    color: _isBluetoothConnected ? Colors.green : Colors.red,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _connectedDeviceName,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEarbudConfiguration() {
    return Column(
      children: [
        const Text(
          'Earbud Language Configuration',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),

        // Left Earbud
        _buildEarbudSelector(
            'left', 'Left Earbud', _leftEarbudColor, Icons.headset),
        const SizedBox(height: 16),

        // Right Earbud
        _buildEarbudSelector(
            'right', 'Right Earbud', _rightEarbudColor, Icons.headset),
      ],
    );
  }

  Widget _buildEarbudSelector(
      String side, String label, Color color, IconData icon) {
    final selectedLanguage =
        _earbudLanguages[side] ?? _supportedLanguages.first;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonHideUnderline(
            child: DropdownButton<config_service.Language>(
              value: selectedLanguage,
              dropdownColor: const Color(0xFF1D1E33),
              isExpanded: true,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              icon: Icon(Icons.arrow_drop_down, color: color),
              items:
                  _supportedLanguages.map((config_service.Language language) {
                return DropdownMenuItem<config_service.Language>(
                  value: language,
                  child: Row(
                    children: [
                      Text(language.nativeName),
                      const SizedBox(width: 8),
                      Text(
                        '(${language.name})',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (config_service.Language? newValue) {
                if (newValue != null) {
                  setState(() {
                    _earbudLanguages[side] = newValue;
                  });
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingButton() {
    return Column(
      children: [
        if (_isRecording) ...[
          AnimatedBuilder(
            animation: _waveAnimation,
            builder: (context, child) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 4,
                    height:
                        20 + (20 * (((_waveAnimation.value + index / 5) % 1))),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00D9FF),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  );
                }),
              );
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'Recording...',
            style: TextStyle(
              color: Color(0xFF00D9FF),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
        ],
        GestureDetector(
          onTap: _toggleRecording,
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _isRecording ? _pulseAnimation.value : 1.0,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: _isRecording
                          ? [const Color(0xFFFF1744), const Color(0xFFD50000)]
                          : [const Color(0xFF00D9FF), const Color(0xFF0091EA)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (_isRecording
                                ? const Color(0xFFFF1744)
                                : const Color(0xFF00D9FF))
                            .withOpacity(0.5),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isRecording ? Icons.stop : Icons.mic,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _isRecording ? 'Tap to stop recording' : 'Tap to start recording',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildPlaybackControls() {
    return Column(
      children: [
        const Text(
          'Playback Controls',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            // Left Channel Playback
            Expanded(
              child: _buildChannelPlayback(
                'Left Earbud',
                _leftEarbudColor,
                _isPlayingLeft,
                _playLeftChannel,
              ),
            ),
            const SizedBox(width: 16),

            // Right Channel Playback
            Expanded(
              child: _buildChannelPlayback(
                'Right Earbud',
                _rightEarbudColor,
                _isPlayingRight,
                _playRightChannel,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChannelPlayback(
      String label, Color color, bool isPlaying, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1D1E33),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPlaying ? color : color.withOpacity(0.3),
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              isPlaying ? Icons.stop_circle : Icons.play_circle,
              color: color,
              size: 48,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isPlaying ? 'Playing...' : 'Tap to play',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
