import 'dart:typed_data';

import 'google_stt_service.dart';
import 'stt_provider.dart';

class GoogleSttProvider implements SttProvider {
  final GoogleSttService _svc = GoogleSttService();

  @override
  Future<bool> initialize() => _svc.initialize();

  @override
  Future<DiarizationResult?> transcribeWithDiarization({
    required Uint8List audioBytes,
    required String languageCode,
    List<String>? alternativeLanguages,
    int minSpeakers = 2,
    int maxSpeakers = 6,
  }) {
    return _svc.transcribeWithDiarization(
      audioBytes: audioBytes,
      languageCode: languageCode,
      alternativeLanguages: alternativeLanguages,
      minSpeakers: minSpeakers,
      maxSpeakers: maxSpeakers,
    );
  }
}
