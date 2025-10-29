import 'dart:typed_data';

import 'google_stt_service.dart';

abstract class SttProvider {
  Future<bool> initialize();

  Future<DiarizationResult?> transcribeWithDiarization({
    required Uint8List audioBytes,
    required String languageCode,
    List<String>? alternativeLanguages,
    int minSpeakers = 2,
    int maxSpeakers = 6,
  });
}
