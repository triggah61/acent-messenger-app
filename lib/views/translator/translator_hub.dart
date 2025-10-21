import 'package:flutter/material.dart';
import 'on_screen_translator.dart';
import 'stereo_translator.dart';
import 'google_stt_translator.dart';
import 'native_stt_translator.dart';

class TranslatorHub extends StatelessWidget {
  const TranslatorHub({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        title: const Text('Translation Services'),
        backgroundColor: const Color(0xFF1D1E33),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              const Text(
                'Choose Translation Mode',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // On-Screen Translator Card
              _buildTranslatorCard(
                context,
                title: 'On-Screen Translator',
                description:
                    'Record conversations with speaker diarization and multi-language support',
                icon: Icons.screen_share,
                color: const Color(0xFF00D9FF),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const OnScreenTranslator(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),

              // Stereo Translator Card
              _buildTranslatorCard(
                context,
                title: 'Stereo Translator',
                description:
                    'Use Bluetooth stereo headset for dual-channel translation with separate earbuds',
                icon: Icons.headset,
                color: const Color(0xFFE91E63),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const StereoTranslator(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),

              // Google STT Translator Card
              _buildTranslatorCard(
                context,
                title: 'Google STT Translation',
                description:
                    'Record 2 speakers with Google STT diarization, auto-separate voices, and play back each speaker',
                icon: Icons.cloud_queue,
                color: const Color(0xFF4CAF50),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const GoogleSTTTranslator(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),

              // Native STT Translator Card
              _buildTranslatorCard(
                context,
                title: 'Native STT Translation',
                description:
                    'Record 2 speakers, auto-separate their voices, and play back each speaker individually',
                icon: Icons.speaker_notes,
                color: const Color(0xFFFF9800),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NativeSTTTranslator(),
                    ),
                  );
                },
              ),

              // Add bottom padding for better scrolling experience
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTranslatorCard(
    BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1D1E33),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3), width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    color,
                    color.withOpacity(0.6),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.5),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 35,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Tap to open',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.arrow_forward,
                  color: color,
                  size: 14,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
