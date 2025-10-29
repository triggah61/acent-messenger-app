import 'package:flutter/material.dart';

import '../../services/assemblyai_stt_service.dart';
import '../../services/stt_provider.dart';
import 'google_stt_translator.dart' as google_ui;

/// Wrapper screen that reuses the Google STT translator UI and pipeline,
/// but swaps the STT provider with AssemblyAI for automatic language detection.
class AssemblyAiSttTranslator extends StatefulWidget {
  const AssemblyAiSttTranslator({super.key});

  @override
  State<AssemblyAiSttTranslator> createState() =>
      _AssemblyAiSttTranslatorState();
}

class _AssemblyAiSttTranslatorState extends State<AssemblyAiSttTranslator> {
  late final SttProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = AssemblyAiSttService();
  }

  @override
  Widget build(BuildContext context) {
    // The Google translator supports dependency injection via providerCtor if available.
    return google_ui.GoogleSTTTranslator(provider: _provider);
  }
}
