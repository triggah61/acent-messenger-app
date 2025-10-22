# Stereo Audio Implementation Guide

## Overview

This guide provides a comprehensive implementation for merging two mono TTS audio files into a stereo file with left and right channel separation for earpiece-specific playback. The solution uses `ffmpeg_kit_flutter` and `path_provider` to create professional-quality stereo audio files.

## Architecture

### Core Components

1. **StereoAudioService** - Handles FFmpeg-based audio merging
2. **EnhancedTtsService** - Extends TTS functionality with stereo support
3. **Integration Examples** - Complete usage demonstrations

### Audio Flow

```
Mono TTS Audio 1 (Left Channel)  ──┐
                                   ├── FFmpeg ──► Stereo Audio File
Mono TTS Audio 2 (Right Channel) ──┘
```

## Implementation Details

### 1. StereoAudioService

**Purpose**: Core service for merging mono audio files into stereo using FFmpeg.

**Key Features**:
- FFmpeg-based audio processing
- Channel layout configuration (stereo)
- Volume control for individual channels
- File validation and error handling
- Temporary file cleanup

**Core Method**:
```dart
Future<String?> createStereoAudioFile(
  String leftAudioPath,
  String rightAudioPath, {
  String? outputFileName,
}) async
```

**FFmpeg Command**:
```bash
-i "left_audio.wav" -i "right_audio.wav" 
-filter_complex "[0:a][1:a]join=inputs=2:channel_layout=stereo[a]" 
-map "[a]" 
-acodec pcm_s16le 
-ar 44100 
-y 
"output_stereo.wav"
```

### 2. EnhancedTtsService

**Purpose**: Extended TTS service with stereo audio generation capabilities.

**Key Features**:
- Mono audio file generation
- Stereo audio file creation
- Multi-language support
- Volume control
- Integration with StereoAudioService

**Core Method**:
```dart
Future<String?> generateStereoAudioFile(
  String leftText,
  String rightText,
  String leftLanguageCode,
  String rightLanguageCode, {
  String? outputFileName,
  double leftVolume = 1.0,
  double rightVolume = 1.0,
}) async
```

### 3. Integration with Google STT Translator

**Use Case**: Separate earpiece audio for translated conversations.

**Implementation**:
```dart
// Generate stereo audio for Google STT Translator
final stereoPath = await _enhancedTtsService.generateStereoAudioFile(
  speaker1TranslatedText,  // Left channel
  speaker2TranslatedText,  // Right channel
  speaker1TargetLanguage,  // Left channel language
  speaker2TargetLanguage,  // Right channel language
  outputFileName: 'google_stt_stereo_${timestamp}.wav',
  leftVolume: 1.0,
  rightVolume: 1.0,
);
```

## Technical Specifications

### Audio Format
- **Codec**: PCM 16-bit signed little-endian
- **Sample Rate**: 44.1 kHz
- **Channels**: 2 (Stereo)
- **Channel Layout**: Left channel (Speaker 1), Right channel (Speaker 2)

### FFmpeg Configuration
- **Filter**: `join=inputs=2:channel_layout=stereo`
- **Mapping**: `[0:a][1:a]` → `[a]`
- **Output**: Stereo WAV file

### File Handling
- **Input**: Two mono WAV files
- **Output**: Single stereo WAV file
- **Temporary Files**: Automatically cleaned up
- **Storage**: Application documents directory

## Usage Examples

### Basic Stereo Audio Generation

```dart
// Initialize services
final enhancedTtsService = EnhancedTtsService();
await enhancedTtsService.initialize();

// Generate stereo audio
final stereoPath = await enhancedTtsService.generateStereoAudioFile(
  'Hello, this is the left channel.',
  'Hello, this is the right channel.',
  'en', // Left channel language
  'en', // Right channel language
  outputFileName: 'my_stereo_audio.wav',
  leftVolume: 1.0,
  rightVolume: 1.0,
);

// Play stereo audio
if (stereoPath != null) {
  await enhancedTtsService.playStereoAudio(stereoPath);
}
```

### Multi-language Stereo Audio

```dart
// Generate stereo audio with different languages
final stereoPath = await enhancedTtsService.generateStereoAudioFile(
  'হ্যালো, এটি বাম চ্যানেলের অডিও।', // Bengali
  'Hello, this is the right channel audio.', // English
  'bn', // Left channel language (Bengali)
  'en', // Right channel language (English)
  outputFileName: 'multilang_stereo.wav',
  leftVolume: 0.8,
  rightVolume: 1.0,
);
```

### Google STT Translator Integration

```dart
// In Google STT Translator
Future<void> _generateStereoAudioForTranslator() async {
  // Get translation results
  final speaker1Translation = _translations[0]; // Speaker 1's translated text
  final speaker2Translation = _translations[1]; // Speaker 2's translated text
  
  // Get target languages
  final speaker1TargetLang = _speakerLanguages[1]?.code; // For Speaker 2 to hear
  final speaker2TargetLang = _speakerLanguages[0]?.code; // For Speaker 1 to hear
  
  // Generate stereo audio
  final stereoPath = await _enhancedTtsService.generateStereoAudioFile(
    speaker1Translation,  // Left channel: Speaker 1's translation
    speaker2Translation,  // Right channel: Speaker 2's translation
    speaker1TargetLang,   // Left channel language
    speaker2TargetLang,   // Right channel language
    outputFileName: 'translator_stereo_${DateTime.now().millisecondsSinceEpoch}.wav',
  );
  
  // Store for playback
  if (stereoPath != null) {
    _stereoAudioPath = stereoPath;
  }
}
```

## Error Handling

### Common Issues and Solutions

1. **FFmpeg Not Available**
   ```dart
   // Test FFmpeg functionality
   final isWorking = await _stereoAudioService.testFFmpegFunctionality();
   if (!isWorking) {
     // Handle FFmpeg not available
   }
   ```

2. **File Not Found**
   ```dart
   // Validate input files
   final leftFile = File(leftAudioPath);
   final rightFile = File(rightAudioPath);
   
   if (!await leftFile.exists() || !await rightFile.exists()) {
     // Handle missing files
   }
   ```

3. **FFmpeg Execution Failed**
   ```dart
   // Check return code
   if (!ReturnCode.isSuccess(returnCode)) {
     final logs = await session.getLogs();
     final errorMessage = logs.map((log) => log.getMessage()).join('\n');
     // Handle FFmpeg error
   }
   ```

## Performance Considerations

### Optimization Tips

1. **File Cleanup**: Always clean up temporary files
2. **Memory Management**: Dispose services properly
3. **Error Recovery**: Implement proper error handling
4. **File Validation**: Check file existence before processing

### Best Practices

1. **Initialize Once**: Initialize services once and reuse
2. **Async Operations**: Use proper async/await patterns
3. **Resource Management**: Dispose resources in dispose() method
4. **Error Logging**: Log errors for debugging

## Testing

### Test FFmpeg Functionality

```dart
// Test FFmpeg
final isWorking = await _stereoAudioService.testFFmpegFunctionality();
print('FFmpeg working: $isWorking');

// Get FFmpeg version
final version = await _stereoAudioService.getFFmpegVersion();
print('FFmpeg version: $version');
```

### Test Stereo Audio Generation

```dart
// Test basic stereo audio generation
final stereoPath = await _enhancedTtsService.generateStereoAudioFile(
  'Left channel test',
  'Right channel test',
  'en',
  'en',
);

if (stereoPath != null) {
  print('Stereo audio generated successfully: $stereoPath');
  // Test playback
  await _enhancedTtsService.playStereoAudio(stereoPath);
} else {
  print('Failed to generate stereo audio');
}
```

## Integration with Existing Code

### Google STT Translator Integration

1. **Add EnhancedTtsService** to Google STT Translator
2. **Generate stereo audio** after translation
3. **Store stereo audio path** for playback
4. **Add stereo playback controls** to UI

### Example Integration

```dart
class GoogleSTTTranslator extends StatefulWidget {
  // ... existing code
}

class _GoogleSTTTranslatorState extends State<GoogleSTTTranslator> {
  final EnhancedTtsService _enhancedTtsService = EnhancedTtsService();
  String? _stereoAudioPath;
  
  @override
  void initState() {
    super.initState();
    _enhancedTtsService.initialize();
  }
  
  Future<void> _generateStereoAudio() async {
    // Generate stereo audio after translation
    final stereoPath = await _enhancedTtsService.generateStereoAudioFile(
      _translations[0] ?? '',
      _translations[1] ?? '',
      _speakerLanguages[1]?.code ?? 'en',
      _speakerLanguages[0]?.code ?? 'en',
    );
    
    if (stereoPath != null) {
      setState(() {
        _stereoAudioPath = stereoPath;
      });
    }
  }
  
  Future<void> _playStereoAudio() async {
    if (_stereoAudioPath != null) {
      await _enhancedTtsService.playStereoAudio(_stereoAudioPath!);
    }
  }
  
  @override
  void dispose() {
    _enhancedTtsService.dispose();
    super.dispose();
  }
}
```

## Dependencies

### Required Packages

```yaml
dependencies:
  ffmpeg_kit_flutter: ^6.0.3
  path_provider: ^2.1.3
  audioplayers: ^6.0.0
  flutter_tts: ^3.8.3
```

### Platform Support

- **Android**: Full support
- **iOS**: Full support
- **Web**: Limited support (FFmpeg may not work)
- **Desktop**: Full support

## Conclusion

This implementation provides a complete solution for generating stereo audio files from mono TTS audio with proper channel separation. The solution is production-ready and includes comprehensive error handling, testing capabilities, and integration examples.

The stereo audio functionality enables separate earpiece playback, making it ideal for translation applications where each speaker needs to hear the other's translated speech in their own language.
