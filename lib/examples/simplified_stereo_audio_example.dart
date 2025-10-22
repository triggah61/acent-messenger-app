import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/enhanced_tts_service_simplified.dart';
import '../services/simplified_stereo_audio_service.dart';

/// Comprehensive example demonstrating simplified stereo audio generation and playback
/// for separate earpiece audio (left and right channels) without FFmpeg dependency
class SimplifiedStereoAudioExample extends StatefulWidget {
  const SimplifiedStereoAudioExample({super.key});

  @override
  State<SimplifiedStereoAudioExample> createState() =>
      _SimplifiedStereoAudioExampleState();
}

class _SimplifiedStereoAudioExampleState
    extends State<SimplifiedStereoAudioExample> {
  final EnhancedTtsServiceSimplified _enhancedTtsService =
      EnhancedTtsServiceSimplified();
  final SimplifiedStereoAudioService _stereoAudioService =
      SimplifiedStereoAudioService();

  bool _isInitialized = false;
  bool _isGenerating = false;
  bool _isPlaying = false;
  String _status = 'Ready to generate stereo audio';
  double _leftVolume = 1.0;
  double _rightVolume = 1.0;

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

      // Test stereo audio functionality
      final isWorking =
          await _stereoAudioService.testStereoAudioFunctionality();
      if (isWorking) {
        setState(() {
          _isInitialized = true;
          _status =
              'Services initialized successfully. Ready for stereo audio generation.';
        });
      } else {
        setState(() {
          _status = 'Stereo audio service not working properly.';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Error initializing services: $e';
      });
      debugPrint('Error initializing services: $e');
    }
  }

  /// Example 1: Play stereo audio from text (English)
  Future<void> _playStereoAudioExample1() async {
    if (!_isInitialized) return;

    setState(() {
      _isGenerating = true;
      _status = 'Playing stereo audio (Example 1 - English)...';
    });

    try {
      // Play stereo audio with English text
      final success = await _enhancedTtsService.playStereoAudioFromText(
        _exampleTexts['en']!['left']!,
        _exampleTexts['en']!['right']!,
        'en', // Left channel language
        'en', // Right channel language
        leftVolume: _leftVolume,
        rightVolume: _rightVolume,
      );

      if (success) {
        setState(() {
          _isPlaying = true;
          _status = 'Stereo audio playing successfully!';
        });
        debugPrint('Example 1: Stereo audio playing successfully');
      } else {
        setState(() {
          _status = 'Failed to play stereo audio (Example 1)';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Error playing stereo audio (Example 1): $e';
      });
      debugPrint('Error in Example 1: $e');
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  /// Example 2: Play stereo audio with different languages
  Future<void> _playStereoAudioExample2() async {
    if (!_isInitialized) return;

    setState(() {
      _isGenerating = true;
      _status = 'Playing stereo audio (Example 2 - Multi-language)...';
    });

    try {
      // Play stereo audio with Bengali and Urdu
      final success = await _enhancedTtsService.playStereoAudioFromText(
        _exampleTexts['bn']!['left']!,
        _exampleTexts['ur']!['right']!,
        'bn', // Left channel language (Bengali)
        'ur', // Right channel language (Urdu)
        leftVolume: _leftVolume,
        rightVolume: _rightVolume,
      );

      if (success) {
        setState(() {
          _isPlaying = true;
          _status = 'Multi-language stereo audio playing successfully!';
        });
        debugPrint(
            'Example 2: Multi-language stereo audio playing successfully');
      } else {
        setState(() {
          _status = 'Failed to play multi-language stereo audio (Example 2)';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Error playing multi-language stereo audio (Example 2): $e';
      });
      debugPrint('Error in Example 2: $e');
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  /// Example 3: Play stereo audio with volume control
  Future<void> _playStereoAudioExample3() async {
    if (!_isInitialized) return;

    setState(() {
      _isGenerating = true;
      _status = 'Playing stereo audio (Example 3 - Volume Control)...';
    });

    try {
      // Play stereo audio with different volume levels
      final success = await _enhancedTtsService.playStereoAudioFromText(
        _exampleTexts['hi']!['left']!,
        _exampleTexts['en']!['right']!,
        'hi', // Left channel language (Hindi)
        'en', // Right channel language (English)
        leftVolume: 0.6, // Lower volume for left channel
        rightVolume: 1.0, // Full volume for right channel
      );

      if (success) {
        setState(() {
          _isPlaying = true;
          _status = 'Volume-controlled stereo audio playing successfully!';
        });
        debugPrint(
            'Example 3: Volume-controlled stereo audio playing successfully');
      } else {
        setState(() {
          _status = 'Failed to play volume-controlled stereo audio (Example 3)';
        });
      }
    } catch (e) {
      setState(() {
        _status =
            'Error playing volume-controlled stereo audio (Example 3): $e';
      });
      debugPrint('Error in Example 3: $e');
    } finally {
      setState(() {
        _isGenerating = false;
      });
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

  /// Pause stereo audio playback
  Future<void> _pauseStereoAudio() async {
    try {
      await _enhancedTtsService.pause();
      setState(() {
        _status = 'Stereo audio playback paused.';
      });
    } catch (e) {
      debugPrint('Error pausing stereo audio: $e');
    }
  }

  /// Resume stereo audio playback
  Future<void> _resumeStereoAudio() async {
    try {
      await _enhancedTtsService.resume();
      setState(() {
        _status = 'Stereo audio playback resumed.';
      });
    } catch (e) {
      debugPrint('Error resuming stereo audio: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simplified Stereo Audio Example'),
        backgroundColor: Colors.purple,
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

            // Volume Controls
            Text(
              'Volume Controls',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),

            // Left Channel Volume
            Row(
              children: [
                const Icon(Icons.headphones, color: Colors.blue),
                const SizedBox(width: 8),
                const Text('Left Channel:'),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: _leftVolume,
                    min: 0.0,
                    max: 1.0,
                    divisions: 10,
                    label: '${(_leftVolume * 100).round()}%',
                    onChanged: (value) {
                      setState(() {
                        _leftVolume = value;
                      });
                    },
                  ),
                ),
                Text('${(_leftVolume * 100).round()}%'),
              ],
            ),

            // Right Channel Volume
            Row(
              children: [
                const Icon(Icons.headphones, color: Colors.orange),
                const SizedBox(width: 8),
                const Text('Right Channel:'),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: _rightVolume,
                    min: 0.0,
                    max: 1.0,
                    divisions: 10,
                    label: '${(_rightVolume * 100).round()}%',
                    onChanged: (value) {
                      setState(() {
                        _rightVolume = value;
                      });
                    },
                  ),
                ),
                Text('${(_rightVolume * 100).round()}%'),
              ],
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
                  ? _playStereoAudioExample1
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
                  ? _playStereoAudioExample2
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
                  ? _playStereoAudioExample3
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
            if (_isPlaying) ...[
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
                      onPressed: _pauseStereoAudio,
                      icon: const Icon(Icons.pause),
                      label: const Text('Pause'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _resumeStereoAudio,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Resume'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _stopStereoAudio,
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

              // Usage Instructions
              Card(
                color: Colors.amber.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info, color: Colors.amber.shade700),
                          const SizedBox(width: 8),
                          Text(
                            'Usage Instructions',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber.shade700,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '• Left Channel: Plays through left earpiece/headphone\n'
                        '• Right Channel: Plays through right earpiece/headphone\n'
                        '• Use headphones or earpieces to experience separate channel audio\n'
                        '• Adjust volume sliders to control individual channel volumes\n'
                        '• This provides stereo-like experience without FFmpeg dependency',
                        style: TextStyle(fontSize: 14),
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
                    Text('Generating and playing stereo audio...'),
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
