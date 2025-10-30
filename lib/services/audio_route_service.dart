import 'package:flutter/services.dart';

class AudioRouteService {
  static const MethodChannel _channel = MethodChannel('audio_route');

  /// Force using the phone's built‑in microphone even if a Bluetooth headset
  /// is connected. On Android this disables SCO and routes input to MIC.
  /// On iOS this sets the preferred input to the built‑in mic.
  static Future<void> forcePhoneMic() async {
    try {
      await _channel.invokeMethod('forcePhoneMic');
    } catch (_) {
      // If the platform method is not available, ignore silently.
    }
  }
}
