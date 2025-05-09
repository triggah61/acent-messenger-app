import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  RecordScreenState createState() => RecordScreenState();
}

class RecordScreenState extends State<RecordScreen> {
  bool _isRecording = false;
  String _recordingStatus = 'Tap to Start Recording';
  final String _dummyAudioPath = 'audio/dummy_audio.mp3'; // Replace with actual path
  double _recordingProgress = 0.0; // Simulate recording progress

  @override
  void initState() {
    super.initState();
    // Simulate recording progress updates
    Future.delayed(Duration.zero, () {
      if (mounted) {
        _simulateRecordingProgress();
      }
    });
  }

  void _simulateRecordingProgress() async {
    while (_isRecording && mounted) {
      await Future.delayed(const Duration(milliseconds: 200)); // Update freq
      setState(() {
        _recordingProgress = (_recordingProgress + 0.01) % 1.0; //Loop progress
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Audio'),
        backgroundColor: Colors.grey[900],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: CircularProgressIndicator(
                    value: _recordingProgress,
                    strokeWidth: 8,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                ),
                IconButton(
                  icon: FaIcon(
                    _isRecording ? FontAwesomeIcons.circleStop : FontAwesomeIcons.microphone,
                    size: 60,
                    color: _isRecording ? Colors.red : Colors.green,
                  ),
                  onPressed: () {
                    setState(() {
                      if (_isRecording) {
                        _isRecording = false;
                        _recordingStatus = 'Recording Stopped';
                        _recordingProgress = 0.0; //Reset progress
                      } else {
                        _isRecording = true;
                        _recordingStatus = 'Recording...';
                        _simulateRecordingProgress(); //Start progress sim
                      }
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              _recordingStatus,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context, _dummyAudioPath);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              icon: const FaIcon(FontAwesomeIcons.paperPlane, color: Colors.white),
              label: const Text('Send Audio', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
      
    );
  }
}