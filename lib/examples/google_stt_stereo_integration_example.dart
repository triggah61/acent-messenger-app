import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/enhanced_tts_service.dart';
import '../services/stereo_audio_service.dart';

/// Integration example showing how to use stereo audio in Google STT Translator
/// This demonstrates the complete workflow for earpiece-specific audio playback
class GoogleSttStereoIntegrationExample extends StatefulWidget {
  const GoogleSttStereoIntegrationExample({super.key});

  @override
  State<GoogleSttStereoIntegrationExample> createState() =>
      _GoogleSttStereoIntegrationExampleState();
}

class _GoogleSttStereoIntegrationExampleState
    extends State<GoogleSttStereoIntegrationExample> {
  final EnhancedTtsService _enhancedTtsService = EnhancedTtsService();
  final StereoAudioService _stereoAudioService = StereoAudioService();

  bool _isInitialized = false;
  bool _isGenerating = false;
  bool _isPlaying = false;
  String? _stereoAudioPath;
  String _status = 'Ready to generate stereo audio';

  // Simulated translation results (as would come from Google STT Translator)
  final Map<String, Map<String, String>> _simulatedTranslationResults = {
    'speaker1': {
      'original': 'Hello, how are you today?',
      'translated': 'হ্যালো, আজ আপনি কেমন আছেন?', // Bengali
      'language': 'en',
      'targetLanguage': 'bn',
    },
    'speaker2': {
      'original': 'আমি ভালো আছি, ধন্যবাদ।', // Bengali
      'translated': 'I am fine, thank you.',
      'language': 'bn',
      'targetLanguage': 'en',
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
        setState(() {
          _isInitialized = true;
          _status =
              'Services initialized successfully. Ready for stereo audio generation.';
        });
      } else {
        setState(() {
          _status = 'FFmpeg not working properly. Please check installation.';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Error initializing services: $e';
      });
      debugPrint('Error initializing services: $e');
    }
  }

  /// Generate stereo audio for Google STT Translator scenario
  /// This simulates the real-world usage in the translator
  Future<void> _generateGoogleSttStereoAudio() async {
    if (!_isInitialized) return;

    setState(() {
      _isGenerating = true;
      _status = 'Generating stereo audio for Google STT Translator...';
    });

    try {
      // Extract translation data
      final speaker1Data = _simulatedTranslationResults['speaker1']!;
      final speaker2Data = _simulatedTranslationResults['speaker2']!;

      debugPrint('GoogleSttStereoIntegration: Generating stereo audio...');
      debugPrint(
          '  Speaker 1 (Left Channel): "${speaker1Data['translated']}" in ${speaker1Data['targetLanguage']}');
      debugPrint(
          '  Speaker 2 (Right Channel): "${speaker2Data['translated']}" in ${speaker2Data['targetLanguage']}');

      // Generate stereo audio file
      // Left channel: Speaker 1's translated text (for Speaker 2 to hear)
      // Right channel: Speaker 2's translated text (for Speaker 1 to hear)
      final stereoPath = await _enhancedTtsService.generateStereoAudioFile(
        speaker1Data['translated']!, // Left channel: Speaker 1's translation
        speaker2Data['translated']!, // Right channel: Speaker 2's translation
        speaker1Data['targetLanguage']!, // Left channel language
        speaker2Data['targetLanguage']!, // Right channel language
        outputFileName:
            'google_stt_stereo_${DateTime.now().millisecondsSinceEpoch}.wav',
        leftVolume: 1.0,
        rightVolume: 1.0,
      );

      if (stereoPath != null) {
        setState(() {
          _stereoAudioPath = stereoPath;
          _status =
              'Stereo audio generated successfully for Google STT Translator!';
        });
        debugPrint(
            'GoogleSttStereoIntegration: Stereo audio generated at: $stereoPath');
      } else {
        setState(() {
          _status = 'Failed to generate stereo audio for Google STT Translator';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Error generating stereo audio: $e';
      });
      debugPrint('Error in GoogleSttStereoIntegration: $e');
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
        title: const Text('Google STT Stereo Integration'),
        backgroundColor: Colors.green,
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

            // Translation Results Display
            Text(
              'Simulated Translation Results',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),

            // Speaker 1 Card
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Speaker 1 (Left Channel)',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildTranslationRow(
                      'Original (EN):',
                      _simulatedTranslationResults['speaker1']!['original']!,
                      Colors.grey.shade600,
                    ),
                    const SizedBox(height: 8),
                    _buildTranslationRow(
                      'Translated (BN):',
                      _simulatedTranslationResults['speaker1']!['translated']!,
                      Colors.blue.shade700,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Speaker 2 Card
            Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Speaker 2 (Right Channel)',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade700,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildTranslationRow(
                      'Original (BN):',
                      _simulatedTranslationResults['speaker2']!['original']!,
                      Colors.grey.shade600,
                    ),
                    const SizedBox(height: 8),
                    _buildTranslationRow(
                      'Translated (EN):',
                      _simulatedTranslationResults['speaker2']!['translated']!,
                      Colors.orange.shade700,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Generate Stereo Audio Button
            ElevatedButton.icon(
              onPressed: _isInitialized && !_isGenerating
                  ? _generateGoogleSttStereoAudio
                  : null,
              icon: const Icon(Icons.audiotrack),
              label:
                  const Text('Generate Stereo Audio for Google STT Translator'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
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
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Generated Stereo Audio File',
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
                        '• Left Channel: Speaker 1\'s translated text (Bengali) - for Speaker 2 to hear\n'
                        '• Right Channel: Speaker 2\'s translated text (English) - for Speaker 1 to hear\n'
                        '• Use headphones or earpieces to experience separate channel audio\n'
                        '• This simulates the real Google STT Translator stereo audio functionality',
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
                    Text(
                        'Generating stereo audio for Google STT Translator...'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranslationRow(String label, String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _enhancedTtsService.dispose();
    _stereoAudioService.dispose();
    super.dispose();
  }
}
