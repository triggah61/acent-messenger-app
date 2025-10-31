import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Set up audio route channel for recording/playback routing control
    let controller = window?.rootViewController as! FlutterViewController
    let audioRouteChannel = FlutterMethodChannel(
      name: "audio_route",
      binaryMessenger: controller.binaryMessenger
    )
    
    audioRouteChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "forcePhoneMic":
        self?.forcePhoneMic(result: result)
      case "enterRecordingRoute":
        self?.enterRecordingRoute(result: result)
      case "enterPlaybackRoute":
        self?.enterPlaybackRoute(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  /// Force using built-in phone microphone (recording phase)
  private func forcePhoneMic(result: @escaping FlutterResult) {
    do {
      let audioSession = AVAudioSession.sharedInstance()
      
      // Set category for recording with bluetooth output allowed
      try audioSession.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
      
      // Override to use built-in mic (not bluetooth mic)
      try audioSession.overrideOutputAudioPort(.none)
      try audioSession.setPreferredInput(nil)  // Use default input (built-in mic)
      
      // Activate session
      try audioSession.setActive(true, options: [])
      
      NSLog("✅ iOS: Forced built-in phone mic for recording")
      result(true)
    } catch {
      NSLog("❌ iOS: Error forcing phone mic: \(error.localizedDescription)")
      result(FlutterError(code: "AUDIO_ROUTE_ERROR", message: error.localizedDescription, details: nil))
    }
  }
  
  /// Enter recording route - use built-in phone mic
  private func enterRecordingRoute(result: @escaping FlutterResult) {
    do {
      let audioSession = AVAudioSession.sharedInstance()
      
      // Set category for recording with bluetooth output allowed (for monitoring)
      try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
      
      // Override to use built-in mic (not bluetooth mic/headset mic)
      try audioSession.overrideOutputAudioPort(.none)
      
      // Get available inputs and select built-in microphone
      if let availableInputs = audioSession.availableInputs {
        for input in availableInputs {
          // Look for built-in microphone
          if input.portType == .builtInMic {
            try audioSession.setPreferredInput(input)
            NSLog("✅ iOS: Set preferred input to built-in mic: \(input.portName)")
            break
          }
        }
      }
      
      // Activate session
      try audioSession.setActive(true, options: [])
      
      NSLog("✅ iOS: Entered recording route (built-in mic)")
      result(true)
    } catch {
      NSLog("❌ iOS: Error entering recording route: \(error.localizedDescription)")
      result(FlutterError(code: "AUDIO_ROUTE_ERROR", message: error.localizedDescription, details: nil))
    }
  }
  
  /// Enter playback route - prefer bluetooth/TWS earpieces for stereo audio
  private func enterPlaybackRoute(result: @escaping FlutterResult) {
    do {
      let audioSession = AVAudioSession.sharedInstance()
      
      // Set category for playback with bluetooth support
      // Use .playback mode for best stereo quality on TWS
      try audioSession.setCategory(.playback, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])
      
      // Clear any output overrides to allow bluetooth/TWS routing
      try audioSession.overrideOutputAudioPort(.none)
      
      // Clear input preference (not needed for playback)
      try audioSession.setPreferredInput(nil)
      
      // Activate session
      try audioSession.setActive(true, options: [])
      
      NSLog("✅ iOS: Entered playback route (prefer BT A2DP/TWS for stereo)")
      result(true)
    } catch {
      NSLog("❌ iOS: Error entering playback route: \(error.localizedDescription)")
      result(FlutterError(code: "AUDIO_ROUTE_ERROR", message: error.localizedDescription, details: nil))
    }
  }
}
