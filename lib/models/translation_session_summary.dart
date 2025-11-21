/// Session summary model for translation usage tracking
/// Pricing based on Soniox real-time API: https://soniox.com/pricing
class TranslationSessionSummary {
  // Time Metrics
  final DateTime sessionStart;
  final DateTime sessionEnd;
  final Duration totalDuration;
  
  // Usage Metrics (Soniox token-based)
  final double audioSecondsProcessed; // Audio duration
  final int inputAudioTokens; // Audio tokens (8.333 tokens/second)
  final int outputTextTokens; // Text tokens (0.3 tokens/character)
  final int transcriptionCharacters; // Transcription character count
  final int translationCharacters; // Translation character count
  
  // Content Metrics per Speaker
  final Map<int, int> charactersPerSpeaker; // Transcription characters
  final Map<int, int> translationCharactersPerSpeaker; // Translation characters
  final Map<int, String> languagesUsed;
  
  // Cost Metrics (Soniox pricing)
  final double totalCost;
  
  // Quality Metrics
  final int totalTranslations;
  final List<double> translationLatencies;

  TranslationSessionSummary({
    required this.sessionStart,
    required this.sessionEnd,
    required this.totalDuration,
    required this.audioSecondsProcessed,
    required this.inputAudioTokens,
    required this.outputTextTokens,
    required this.transcriptionCharacters,
    required this.translationCharacters,
    required this.charactersPerSpeaker,
    required this.translationCharactersPerSpeaker,
    required this.languagesUsed,
    required this.totalCost,
    required this.totalTranslations,
    required this.translationLatencies,
  });

  /// Calculate average translation latency
  double get averageLatency {
    if (translationLatencies.isEmpty) return 0.0;
    return translationLatencies.reduce((a, b) => a + b) / translationLatencies.length;
  }

  /// Get formatted duration string
  String get formattedDuration {
    final hours = totalDuration.inHours;
    final minutes = totalDuration.inMinutes.remainder(60);
    final seconds = totalDuration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  /// Get formatted cost string
  String get formattedCost {
    return '\$${totalCost.toStringAsFixed(3)}';
  }

  /// Get speaker split percentage based on transcription characters
  Map<int, double> get speakerSplitPercentage {
    final total = charactersPerSpeaker.values.fold(0, (sum, val) => sum + val);
    if (total == 0) return {0: 0.0, 1: 0.0};

    return {
      0: (charactersPerSpeaker[0] ?? 0) / total * 100,
      1: (charactersPerSpeaker[1] ?? 0) / total * 100,
    };
  }
  
  /// Get total characters (transcription + translation)
  int get totalCharacters => transcriptionCharacters + translationCharacters;
}

