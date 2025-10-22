import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/enhanced_tts_service.dart';
import '../services/stereo_audio_service.dart';

/// Comprehensive example demonstrating stereo audio generation and playback
/// for separate earpiece audio (left and right channels)
class StereoAudioExample extends StatefulWidget {
  const StereoAudioExample({super.key});

  @override
  State<StereoAudioExample> createState() => _StereoAudioExampleState();
}

class _StereoAudioExampleState extends State<StereoAudioExample> {
  final EnhancedTtsService _enhancedTtsService = EnhancedTtsService();
  final StereoAudioService _stereoAudioService = StereoAudioService();

  bool _isInitialized = false;
  bool _isGenerating = false;
  bool _isPlaying = false;
  String? _stereoAudioPath;
  String _status = 'Ready to generate stereo audio';

  // Example texts for different languages
  final Map<String, Map<String, String>> _exampleTexts = {
    'en': {
      'left': 'Hello, this is the left channel audio.',
      'right': 'Hello, this is the right channel audio.',
    },
    'bn': {
      'left': 'হ্যালো, এটি বাম চ্যানেলের অডিও।',
      'right': 'হ্যালো, এটি ডান চ্যানেলের অডিও।',
    },
    'ur': {
      'left': 'ہیلو، یہ بائیں چینل کا آڈیو ہے۔',
      'right': 'ہیلو، یہ دائیں چینل کا آڈیو ہے۔',
    },
    'hi': {
      'left': 'नमस्ते, यह बाएं चैनल का ऑडियो है।',
      'right': 'नमस्ते, यह दाएं चैनल का ऑडियो है।',
    },
  };

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      setState(() {
        _status = 'Initializing services...';
      });

      await _enhancedTtsService.initialize();
      await _stereoAudioService.initialize();

      // Test FFmpeg functionality
      final ffmpegWorking = await _stereoAudioService.testFFmpegFunctionality();
      if (ffmpegWorking) {
        final version = await _stereoAudioService.getFFmpegVersion();
        debugPrint('FFmpeg version: $version');
      }

      setState(() {
        _isInitialized = true;
        _status =
            'Services initialized successfully. Ready to generate stereo audio.';
      });
    } catch (e) {
      setState(() {
        _status = 'Error initializing services: $e';
      });
      debugPrint('Error initializing services: $e');
    }
  }

  /// Example 1: Generate stereo audio from two different texts
  Future<void> _generateStereoAudioExample1() async {
    if (!_isInitialized) return;

    setState(() {
      _isGenerating = true;
      _status = 'Generating stereo audio (Example 1)...';
    });

    try {
      // Generate stereo audio with English text
      final stereoPath = await _enhancedTtsService.generateStereoAudioFile(
        _exampleTexts['en']!['left']!,
        _exampleTexts['en']!['right']!,
        'en', // Left channel language
        'en', // Right channel language
        outputFileName: 'example1_stereo_audio.wav',
        leftVolume: 1.0,
        rightVolume: 1.0,
      );

      if (stereoPath != null) {
        setState(() {
          _stereoAudioPath = stereoPath;
          _status = 'Stereo audio generated successfully!';
        });
        debugPrint('Example 1: Stereo audio generated at: $stereoPath');
      } else {
        setState(() {
          _status = 'Failed to generate stereo audio (Example 1)';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Error generating stereo audio (Example 1): $e';
      });
      debugPrint('Error in Example 1: $e');
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  /// Example 2: Generate stereo audio with different languages
  Future<void> _generateStereoAudioExample2() async {
    if (!_isInitialized) return;

    setState(() {
      _isGenerating = true;
      _status = 'Generating stereo audio (Example 2 - Multi-language)...';
    });

    try {
      // Generate stereo audio with Bengali and Urdu
      final stereoPath = await _enhancedTtsService.generateStereoAudioFile(
        _exampleTexts['bn']!['left']!,
        _exampleTexts['ur']!['right']!,
        'bn', // Left channel language (Bengali)
        'ur', // Right channel language (Urdu)
        outputFileName: 'example2_multilang_stereo_audio.wav',
        leftVolume: 0.8,
        rightVolume: 0.8,
      );

      if (stereoPath != null) {
        setState(() {
          _stereoAudioPath = stereoPath;
          _status = 'Multi-language stereo audio generated successfully!';
        });
        debugPrint(
            'Example 2: Multi-language stereo audio generated at: $stereoPath');
      } else {
        setState(() {
          _status =
              'Failed to generate multi-language stereo audio (Example 2)';
        });
      }
    } catch (e) {
      setState(() {
        _status =
            'Error generating multi-language stereo audio (Example 2): $e';
      });
      debugPrint('Error in Example 2: $e');
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  /// Example 3: Generate stereo audio with volume control
  Future<void> _generateStereoAudioExample3() async {
    if (!_isInitialized) return;

    setState(() {
      _isGenerating = true;
      _status = 'Generating stereo audio (Example 3 - Volume Control)...';
    });

    try {
      // Generate stereo audio with different volume levels
      final stereoPath = await _enhancedTtsService.generateStereoAudioFile(
        _exampleTexts['hi']!['left']!,
        _exampleTexts['en']!['right']!,
        'hi', // Left channel language (Hindi)
        'en', // Right channel language (English)
        outputFileName: 'example3_volume_control_stereo_audio.wav',
        leftVolume: 0.6, // Lower volume for left channel
        rightVolume: 1.0, // Full volume for right channel
      );

      if (stereoPath != null) {
        setState(() {
          _stereoAudioPath = stereoPath;
          _status = 'Volume-controlled stereo audio generated successfully!';
        });
        debugPrint(
            'Example 3: Volume-controlled stereo audio generated at: $stereoPath');
      } else {
        setState(() {
          _status =
              'Failed to generate volume-controlled stereo audio (Example 3)';
        });
      }
    } catch (e) {
      setState(() {
        _status =
            'Error generating volume-controlled stereo audio (Example 3): $e';
      });
      debugPrint('Error in Example 3: $e');
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  /// Play the generated stereo audio
  Future<void> _playStereoAudio() async {
    if (_stereoAudioPath == null) return;

    setState(() {
      _isPlaying = true;
      _status = 'Playing stereo audio...';
    });

    try {
      await _enhancedTtsService.playStereoAudio(_stereoAudioPath!);

      // Listen for completion
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _status = 'Stereo audio playback completed.';
          });
        }
      });
    } catch (e) {
      setState(() {
        _isPlaying = false;
        _status = 'Error playing stereo audio: $e';
      });
      debugPrint('Error playing stereo audio: $e');
    }
  }

  /// Stop stereo audio playback
  Future<void> _stopStereoAudio() async {
    try {
      await _enhancedTtsService.stop();
      setState(() {
        _isPlaying = false;
        _status = 'Stereo audio playback stopped.';
      });
    } catch (e) {
      debugPrint('Error stopping stereo audio: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stereo Audio Example'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            Card(
              color: _isInitialized ? Colors.green.shade50 : Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _status,
                      style: TextStyle(
                        color: _isInitialized
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Example Buttons
            Text(
              'Examples',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),

            // Example 1: Basic Stereo Audio
            ElevatedButton.icon(
              onPressed: _isInitialized && !_isGenerating
                  ? _generateStereoAudioExample1
                  : null,
              icon: const Icon(Icons.audiotrack),
              label: const Text('Example 1: Basic Stereo Audio (English)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),

            const SizedBox(height: 12),

            // Example 2: Multi-language Stereo Audio
            ElevatedButton.icon(
              onPressed: _isInitialized && !_isGenerating
                  ? _generateStereoAudioExample2
                  : null,
              icon: const Icon(Icons.language),
              label: const Text('Example 2: Multi-language (Bengali + Urdu)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),

            const SizedBox(height: 12),

            // Example 3: Volume Control
            ElevatedButton.icon(
              onPressed: _isInitialized && !_isGenerating
                  ? _generateStereoAudioExample3
                  : null,
              icon: const Icon(Icons.volume_up),
              label: const Text('Example 3: Volume Control (Hindi + English)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),

            const SizedBox(height: 20),

            // Playback Controls
            if (_stereoAudioPath != null) ...[
              Text(
                'Playback Controls',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: !_isPlaying ? _playStereoAudio : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Play Stereo Audio'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isPlaying ? _stopStereoAudio : null,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Audio File Info
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Generated Audio File',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _stereoAudioPath!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const Spacer(),

            // Loading Indicator
            if (_isGenerating)
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Generating stereo audio...'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _enhancedTtsService.dispose();
    _stereoAudioService.dispose();
    super.dispose();
  }
}
