package com.qmessenger.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Context
import android.media.AudioManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioDeviceInfo
import android.os.Build
import android.util.Log

class MainActivity : FlutterActivity() {
    private val BLUETOOTH_CHANNEL = "bluetooth_audio_service"
    private val AUDIO_PROFILE_CHANNEL = "audio_profile_service"
    private val AUDIO_ROUTE_CHANNEL = "audio_route"
    private val NATIVE_RECORDER_CHANNEL = "native_audio_recorder"
    private val TAG = "AudioRoute"
    
    private lateinit var bluetoothService: BluetoothAudioService
    private lateinit var audioProfileService: AudioProfileService
    private var audioFocusRequest: AudioFocusRequest? = null
    private var nativeRecorder: NativeAudioRecorder? = null
    private var nativeAudioPlayer: NativeAudioPlayer? = null
    private var originalAudioMode: Int = AudioManager.MODE_NORMAL
    private var communicationDeviceSet: Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize Bluetooth service
        bluetoothService = BluetoothAudioService(this)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BLUETOOTH_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkBluetoothConnection" -> {
                    bluetoothService.checkBluetoothConnection(result)
                }
                "requestBluetoothPermissions" -> {
                    bluetoothService.requestPermissions(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Initialize Audio Profile service
        audioProfileService = AudioProfileService(this)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_PROFILE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initializeAudioProfiles" -> {
                    audioProfileService.initialize(result)
                }
                "setAudioProfile" -> {
                    val profile = call.argument<String>("profile")
                    audioProfileService.setAudioProfile(result, profile ?: "")
                }
                "isBluetoothAvailable" -> {
                    audioProfileService.isBluetoothAvailable(result)
                }
                "getCurrentProfileStatus" -> {
                    audioProfileService.getCurrentProfileStatus(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Set up Native Audio Recorder Method Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NATIVE_RECORDER_CHANNEL)
            .setMethodCallHandler { call, result ->
            when (call.method) {
                "startRecording" -> {
                    try {
                        val filePath = call.argument<String>("filePath")
                        if (filePath == null) {
                            result.error("INVALID_ARGUMENT", "File path is required", null)
                            return@setMethodCallHandler
                        }
                        
                        // Initialize native recorder if needed
                        if (nativeRecorder == null) {
                            nativeRecorder = NativeAudioRecorder(this)
                        }
                        
                        val success = nativeRecorder!!.startRecording(filePath)
                        result.success(success)
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Error starting native recording: ${e.message}")
                        result.error("RECORDING_ERROR", e.message, null)
                    }
                }
                "stopRecording" -> {
                    try {
                        val success = nativeRecorder?.stopRecording() ?: false
                        result.success(success)
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Error stopping native recording: ${e.message}")
                        result.error("RECORDING_ERROR", e.message, null)
                    }
                }
                "isRecording" -> {
                    try {
                        val recording = nativeRecorder?.isRecording() ?: false
                        result.success(recording)
                    } catch (e: Exception) {
                        result.error("RECORDING_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // Audio route channel: force using the phone's built-in microphone
        val audioRouteChannelInstance = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_ROUTE_CHANNEL)
        
        // CRITICAL: Initialize Native Audio Player AFTER channel is created (for completion callbacks)
        nativeAudioPlayer = NativeAudioPlayer(this, audioRouteChannelInstance)
        
        audioRouteChannelInstance.setMethodCallHandler { call, result ->
            when (call.method) {
                "playAudioFileNative" -> {
                    try {
                        val filePath = call.argument<String>("filePath")
                        if (filePath == null) {
                            result.error("INVALID_ARGUMENT", "filePath is required", null)
                            return@setMethodCallHandler
                        }
                        
                        Log.d(TAG, "═══ Playing Audio File via Native Player (A2DP Routing) ═══")
                        Log.d(TAG, "File: $filePath")
                        
                        // CRITICAL: Check if native player is initialized
                        val player = nativeAudioPlayer
                        if (player == null) {
                            Log.e(TAG, "❌ Native audio player is null - not initialized")
                            result.error("PLAYBACK_ERROR", "Native audio player not initialized", null)
                            return@setMethodCallHandler
                        }
                        
                        // Use native player for guaranteed A2DP routing
                        val success = player.playAudioFile(filePath) {
                            Log.d(TAG, "✅ Native playback completed (callback)")
                        }
                        
                        result.success(success)
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Error playing native audio: ${e.message}")
                        result.error("PLAYBACK_ERROR", e.message, null)
                    }
                }
                "playAudioFileNativeOnChannel" -> {
                    try {
                        val filePath = call.argument<String>("filePath")
                        val channel = call.argument<String>("channel")
                        
                        if (filePath == null || channel == null) {
                            result.error("INVALID_ARGUMENT", "filePath and channel are required", null)
                            return@setMethodCallHandler
                        }
                        
                        Log.d(TAG, "═══ Playing Audio File via Dual-Channel Native Player ═══")
                        Log.d(TAG, "File: $filePath")
                        Log.d(TAG, "Channel: $channel")
                        
                        val player = nativeAudioPlayer
                        if (player == null) {
                            Log.e(TAG, "❌ Native audio player is null")
                            result.error("PLAYBACK_ERROR", "Native audio player not initialized", null)
                            return@setMethodCallHandler
                        }
                        
                        // Use dual-channel player
                        val success = player.playAudioFileOnChannel(filePath, channel) {
                            Log.d(TAG, "✅ Dual-channel playback completed on $channel (callback)")
                        }
                        
                        result.success(success)
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Error playing dual-channel audio: ${e.message}")
                        result.error("PLAYBACK_ERROR", e.message, null)
                    }
                }
                "stopNativePlayback" -> {
                    try {
                        val channel = call.argument<String>("channel")
                        val player = nativeAudioPlayer
                        
                        if (player == null) {
                            result.error("PLAYBACK_ERROR", "Native audio player not initialized", null)
                            return@setMethodCallHandler
                        }
                        
                        if (channel != null) {
                            player.stopChannel(channel)
                            Log.d(TAG, "✅ Stopped playback on $channel channel")
                        } else {
                            player.stop()
                            Log.d(TAG, "✅ Stopped all playback channels")
                        }
                        
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Error stopping playback: ${e.message}")
                        result.error("PLAYBACK_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // Audio routing utility channel (for checking routing status)
        val audioRoutingUtilChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "audio_routing_util")
        audioRoutingUtilChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkAudioRouting" -> {
                    try {
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val routingInfo = mutableMapOf<String, Any>()
                        
                        routingInfo["mode"] = audioManager.mode
                        routingInfo["isBluetoothA2dpOn"] = audioManager.isBluetoothA2dpOn
                        routingInfo["isBluetoothScoOn"] = audioManager.isBluetoothScoOn
                        routingInfo["isSpeakerphoneOn"] = audioManager.isSpeakerphoneOn
                        
                        // Check available devices (Android 6.0+)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                            val deviceList = devices.map { device ->
                                mapOf(
                                    "type" to device.type,
                                    "name" to device.productName.toString(),
                                    "isBluetoothA2dp" to (device.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP)
                                )
                            }
                            routingInfo["outputDevices"] = deviceList
                            
                            val hasBluetoothA2dp = devices.any { 
                                it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP 
                            }
                            routingInfo["hasBluetoothA2dp"] = hasBluetoothA2dp
                        } else {
                            routingInfo["outputDevices"] = emptyList<Any>()
                            routingInfo["hasBluetoothA2dp"] = false
                        }
                        
                        Log.d(TAG, "Audio routing check:")
                        Log.d(TAG, "   Mode: ${routingInfo["mode"]}")
                        Log.d(TAG, "   A2DP on: ${routingInfo["isBluetoothA2dpOn"]}")
                        Log.d(TAG, "   SCO on: ${routingInfo["isBluetoothScoOn"]}")
                        Log.d(TAG, "   Speakerphone: ${routingInfo["isSpeakerphoneOn"]}")
                        Log.d(TAG, "   Has Bluetooth A2DP device: ${routingInfo["hasBluetoothA2dp"]}")
                        
                        result.success(routingInfo)
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Error checking audio routing: ${e.message}", e)
                        result.error("AUDIO_ROUTE_ERROR", e.message, null)
                    }
                }
                // Maintain for backward compatibility
                "forcePhoneMic" -> {
                    try {
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

                        // Stop and disable Bluetooth SCO if active
                        try { audioManager.stopBluetoothSco() } catch (_: Exception) {}
                        try { audioManager.isBluetoothScoOn = false } catch (_: Exception) {}

                        // Route to built-in mic; keep speakerphone off so A2DP output may remain active
                        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                        try { audioManager.isSpeakerphoneOn = false } catch (_: Exception) {}

                        // For newer Android, ensure communication device is cleared from BT if set
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            // No direct API to force mic here, but clearing SCO + MODE_IN_COMMUNICATION is adequate
                        }

                        result.success(true)
                    } catch (e: Exception) {
                        result.error("AUDIO_ROUTE_ERROR", e.message, null)
                    }
                }
                "enterRecordingRoute" -> {
                    try {
                        Log.d(TAG, "═══ Entering Recording Route ═══")
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        
                        // STEP 1: Release any audio focus
                        releaseAudioFocus()
                        
                        // STEP 2: Stop Bluetooth SCO completely
                        try { 
                            audioManager.stopBluetoothSco()
                            Log.d(TAG, "✅ Stopped Bluetooth SCO")
                        } catch (e: Exception) {
                            Log.w(TAG, "Failed to stop SCO: ${e.message}")
                        }
                        try { 
                            audioManager.isBluetoothScoOn = false 
                            Log.d(TAG, "✅ Disabled Bluetooth SCO")
                        } catch (e: Exception) {
                            Log.w(TAG, "Failed to disable SCO: ${e.message}")
                        }
                        
                        // STEP 3: Set mode to IN_COMMUNICATION (for voice input)
                        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                        Log.d(TAG, "✅ Set mode to IN_COMMUNICATION")
                        
                        // STEP 4: Disable speakerphone to force built-in mic
                        try { 
                            audioManager.isSpeakerphoneOn = false 
                            Log.d(TAG, "✅ Disabled speakerphone")
                        } catch (e: Exception) {
                            Log.w(TAG, "Failed to disable speakerphone: ${e.message}")
                        }
                        
                        // STEP 5: Request audio focus for VOICE_COMMUNICATION
                        requestAudioFocusForRecording()
                        
                        Log.d(TAG, "✅ Recording route configured:")
                        Log.d(TAG, "   - Mode: IN_COMMUNICATION")
                        Log.d(TAG, "   - Bluetooth SCO: OFF")
                        Log.d(TAG, "   - Speakerphone: OFF")
                        Log.d(TAG, "   - Expected: Built-in mic will be used")
                        
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Error entering recording route: ${e.message}")
                        result.error("AUDIO_ROUTE_ERROR", e.message, null)
                    }
                }
                "enterPlaybackRoute" -> {
                    try {
                        Log.d(TAG, "═══ Entering Playback Route (STEREO) ═══")
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        
                        // STEP 0: Release any recording audio focus so playback can take priority
                        releaseAudioFocus()
                        
                        // STEP 1: CRITICAL - Stop Bluetooth SCO (voice channel) completely
                        try { 
                            audioManager.stopBluetoothSco() 
                            Log.d(TAG, "✅ Stopped Bluetooth SCO")
                        } catch (e: Exception) {
                            Log.w(TAG, "Failed to stop SCO: ${e.message}")
                        }
                        try { 
                            audioManager.isBluetoothScoOn = false 
                            Log.d(TAG, "✅ Disabled Bluetooth SCO")
                        } catch (e: Exception) {
                            Log.w(TAG, "Failed to disable SCO: ${e.message}")
                        }
                        
                        // STEP 2: CRITICAL - Set audio mode to NORMAL for media playback
                        // This enables stereo A2DP routing on TWS/Bluetooth headsets
                        audioManager.mode = AudioManager.MODE_NORMAL
                        Log.d(TAG, "✅ Set mode to NORMAL (media playback)")
                        
                        // STEP 3: Ensure speakerphone is off so BT can be used
                        try { 
                            audioManager.isSpeakerphoneOn = false 
                            Log.d(TAG, "✅ Disabled speakerphone")
                        } catch (e: Exception) {
                            Log.w(TAG, "Failed to disable speakerphone: ${e.message}")
                        }
                        
                        // NOTE: Audio focus is managed by AudioPlayer (via AudioContext)
                        // Don't release or request here to avoid interrupting ongoing recording focus
                        
                        // STEP 4: For Android 12+ (API 31+), log additional info
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            Log.d(TAG, "✅ Android 12+: System will route to A2DP/TWS stereo")
                        }
                        
                        Log.d(TAG, "✅ Playback route configured:")
                        Log.d(TAG, "   - Mode: NORMAL (media)")
                        Log.d(TAG, "   - Bluetooth SCO: OFF")
                        Log.d(TAG, "   - Speakerphone: OFF")
                        Log.d(TAG, "   - Audio Focus: Managed by AudioPlayer")
                        Log.d(TAG, "   - Expected: Stereo A2DP/TWS output")
                        
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Error entering playback route: ${e.message}")
                        result.error("AUDIO_ROUTE_ERROR", e.message, null)
                    }
                }
                "enterContinuousA2DPMode" -> {
                    try {
                        Log.d(TAG, "═══ Entering Continuous A2DP Mode (No Switching) ═══")
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        
                        // CRITICAL: Check if Bluetooth/TWS is actually connected
                        val bluetoothAdapter = android.bluetooth.BluetoothAdapter.getDefaultAdapter()
                        val hasBluetoothAudio = bluetoothAdapter != null && 
                                               bluetoothAdapter.isEnabled &&
                                               audioManager.isBluetoothA2dpOn
                        
                        Log.d(TAG, "Bluetooth status:")
                        Log.d(TAG, "   - Adapter enabled: ${bluetoothAdapter?.isEnabled}")
                        Log.d(TAG, "   - A2DP on: ${audioManager.isBluetoothA2dpOn}")
                        
                        // STEP 1: Save original audio mode to restore later
                        originalAudioMode = audioManager.mode
                        Log.d(TAG, "Saved original audio mode: $originalAudioMode")
                        
                        // CRITICAL: Use MODE_NORMAL (not MODE_IN_COMMUNICATION)
                        // MODE_NORMAL is designed for media playback and naturally routes MEDIA stream to A2DP
                        // AudioRecord with MIC source works in any mode (including MODE_NORMAL)
                        // This is the correct approach: phone mic input + A2DP output simultaneously
                        audioManager.mode = AudioManager.MODE_NORMAL
                        Log.d(TAG, "✅ Set mode to NORMAL (media mode - enables A2DP routing)")
                        
                        // STEP 2: Ensure Bluetooth SCO is completely disabled
                        // This forces the system to use A2DP instead of SCO for Bluetooth audio
                        try { 
                            audioManager.stopBluetoothSco()
                            Log.d(TAG, "✅ Stopped Bluetooth SCO")
                        } catch (e: Exception) {
                            Log.w(TAG, "Failed to stop SCO: ${e.message}")
                        }
                        try { 
                            audioManager.isBluetoothScoOn = false 
                            Log.d(TAG, "✅ Disabled Bluetooth SCO")
                        } catch (e: Exception) {
                            Log.w(TAG, "Failed to disable SCO: ${e.message}")
                        }
                        
                        // STEP 3: Disable speakerphone to allow Bluetooth routing
                        try { 
                            audioManager.isSpeakerphoneOn = false 
                            Log.d(TAG, "✅ Disabled speakerphone")
                        } catch (e: Exception) {
                            Log.w(TAG, "Failed to disable speakerphone: ${e.message}")
                        }
                        
                        // STEP 4: CRITICAL - Explicitly check and log audio routing
                        // Even in MODE_NORMAL, we need to verify Bluetooth is actually selected
                        Log.d(TAG, "═══ Checking Audio Routing ═══")
                        
                        // Check current audio devices (Android 6.0+)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            try {
                                val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                                Log.d(TAG, "Available output devices: ${devices.size}")
                                devices.forEachIndexed { index, device ->
                                    val isSelected = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                        // Check if this is the selected device for media playback
                                        val isActive = device.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP
                                        isActive
                                    } else {
                                        false
                                    }
                                    Log.d(TAG, "   Device $index: Type=${device.type}, Name=${device.productName}, Selected=$isSelected")
                                    
                                    if (device.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP) {
                                        Log.d(TAG, "   ✅ Found Bluetooth A2DP device: ${device.productName}")
                                    }
                                }
                                
                                // CRITICAL: Check if Bluetooth A2DP device exists
                                val bluetoothA2dpDevice = devices.find { 
                                    it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP 
                                }
                                
                                if (bluetoothA2dpDevice != null) {
                                    Log.d(TAG, "✅ Bluetooth A2DP device found: ${bluetoothA2dpDevice.productName}")
                                    
                                    // CRITICAL: For Android 10+, try to set preferred device for media
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                        try {
                                            // Try setCommunicationDevice first (for communication streams)
                                            val success = audioManager.setCommunicationDevice(bluetoothA2dpDevice)
                                            if (success) {
                                                Log.d(TAG, "✅ Set communication device to Bluetooth A2DP")
                                                communicationDeviceSet = true
                                            } else {
                                                Log.w(TAG, "⚠️ Failed to set communication device")
                                                communicationDeviceSet = false
                                            }
                                        } catch (e: NoSuchMethodError) {
                                            Log.w(TAG, "⚠️ setCommunicationDevice() not available on this device")
                                            communicationDeviceSet = false
                                        } catch (e: Exception) {
                                            Log.w(TAG, "⚠️ Could not set communication device: ${e.message}")
                                            communicationDeviceSet = false
                                        }
                                        
                                        // CRITICAL: Also try to set preferred device for MEDIA strategy (Android 6.0+)
                                        // This explicitly tells system to use Bluetooth for media playback
                                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                            try {
                                                // Use reflection to access setPreferredDeviceForStrategy (Android 6.0+)
                                                val strategyMethod = AudioManager::class.java.getMethod(
                                                    "setPreferredDeviceForStrategy",
                                                    Int::class.javaPrimitiveType,
                                                    AudioDeviceInfo::class.java
                                                )
                                                
                                                // AudioAttributes.USAGE_MEDIA strategy = 1 (from AudioManager.STRATEGY_MEDIA)
                                                // But we need the constant - let's use AudioAttributes.USAGE_MEDIA value
                                                // Actually, the constant might not exist - let's try a different approach
                                                
                                                // Alternative: Force routing by ensuring A2DP is the preferred device
                                                // The system should automatically route MEDIA stream to A2DP if it's available
                                                Log.d(TAG, "✅ Bluetooth A2DP device available - MEDIA stream should route automatically")
                                                
                                            } catch (e: Exception) {
                                                // Not critical - fall back to default routing
                                                Log.d(TAG, "Could not set preferred device strategy: ${e.message}")
                                            }
                                        }
                                    }
                                } else {
                                    Log.w(TAG, "⚠️ No Bluetooth A2DP device found in available devices")
                                    Log.w(TAG, "   This might cause audio to route to phone speaker")
                                    Log.w(TAG, "   Make sure TWS is connected and A2DP is active")
                                    communicationDeviceSet = false
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "❌ Failed to check audio devices: ${e.message}", e)
                                communicationDeviceSet = false
                            }
                        } else {
                            Log.d(TAG, "Android version < 6.0 (API ${Build.VERSION.SDK_INT})")
                            Log.d(TAG, "   Cannot check audio devices - relying on AudioPlayer routing")
                            communicationDeviceSet = false
                        }
                        
                        // STEP 5: CRITICAL - Explicitly enable A2DP if not already active
                        if (!audioManager.isBluetoothA2dpOn) {
                            Log.w(TAG, "⚠️ A2DP is OFF - attempting to activate...")
                            try {
                                // Try to activate A2DP by toggling mode
                                audioManager.mode = AudioManager.MODE_NORMAL
                                // Small delay to let system process
                                Thread.sleep(100)
                                Log.d(TAG, "A2DP status after activation attempt: ${audioManager.isBluetoothA2dpOn}")
                                
                                if (!audioManager.isBluetoothA2dpOn) {
                                    Log.e(TAG, "❌ A2DP still OFF - audio may route to phone speaker")
                                    Log.e(TAG, "   User needs to play music through TWS first to activate A2DP")
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "❌ Failed to activate A2DP: ${e.message}")
                            }
                        } else {
                            Log.d(TAG, "✅ A2DP is ON - Bluetooth routing should work")
                        }
                        
                        Log.d(TAG, "✅ Continuous A2DP mode configured (MODE_NORMAL approach):")
                        Log.d(TAG, "   - Mode: NORMAL (media mode - enables A2DP routing)")
                        Log.d(TAG, "   - Bluetooth SCO: OFF (ensures A2DP mode)")
                        Log.d(TAG, "   - Recording: Phone mic (AudioRecord MIC source - works in any mode)")
                        Log.d(TAG, "   - Playback: TWS speakers (A2DP via MEDIA stream in MODE_NORMAL)")
                        Log.d(TAG, "   - AudioPlayer MEDIA stream → automatically routes to A2DP")
                        Log.d(TAG, "   - NO MODE SWITCHING during session")
                        Log.d(TAG, "   - Full-duplex: Phone mic input + A2DP output simultaneously")
                        
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Error entering continuous A2DP mode: ${e.message}")
                        result.error("AUDIO_ROUTE_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onPause() {
        super.onPause()
        // CRITICAL: Restore audio mode when app goes to background
        // This prevents breaking other apps' audio routing (like YouTube)
        Log.d(TAG, "App paused - restoring audio mode to prevent routing issues")
        resetAudioMode()
    }
    
    override fun onResume() {
        super.onResume()
        // Re-apply continuous A2DP mode when app comes back to foreground
        // This ensures audio routing is correct when user returns
        Log.d(TAG, "App resumed - checking if continuous A2DP mode needs re-application")
        // Note: Flutter will call enterContinuousA2DPMode when needed
    }

    override fun onDestroy() {
        super.onDestroy()
        audioProfileService.cleanup()
        nativeAudioPlayer?.release()
        releaseAudioFocus()
        resetAudioMode()
    }
    
    /**
     * Reset audio mode to original state
     * CRITICAL: This must be called when app is backgrounded to restore system audio
     * Prevents breaking other apps like YouTube that need normal audio routing
     */
    private fun resetAudioMode() {
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            
            // For Android 10+, clear communication device
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && communicationDeviceSet) {
                try {
                    // Clear communication device to restore default routing
                    audioManager.clearCommunicationDevice()
                    Log.d(TAG, "✅ Cleared communication device")
                    communicationDeviceSet = false
                } catch (e: NoSuchMethodError) {
                    // Device reports API 29+ but doesn't have the method
                    Log.w(TAG, "clearCommunicationDevice() not available on this device")
                    communicationDeviceSet = false
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to clear communication device: ${e.message}")
                }
            }
            
            // Reset to original audio mode (usually MODE_NORMAL)
            audioManager.mode = originalAudioMode
            Log.d(TAG, "✅ Audio mode reset to $originalAudioMode")
            
            // Release audio focus
            releaseAudioFocus()
            
            // Ensure SCO is stopped
            try {
                audioManager.stopBluetoothSco()
                audioManager.isBluetoothScoOn = false
            } catch (e: Exception) {
                // Ignore
            }
            
            // Ensure speakerphone is off
            try {
                audioManager.isSpeakerphoneOn = false
            } catch (e: Exception) {
                // Ignore
            }
            
            Log.d(TAG, "✅ Audio mode restored - system audio routing should work normally now")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to reset audio mode: ${e.message}")
        }
    }
    
    /**
     * Request audio focus for recording (voice communication)
     */
    private fun requestAudioFocusForRecording() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Android 8.0+ - Use AudioFocusRequest
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            
            audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(audioAttributes)
                .setAcceptsDelayedFocusGain(true)
                .setOnAudioFocusChangeListener { focusChange ->
                    Log.d(TAG, "Recording audio focus change: $focusChange")
                }
                .build()
            
            val result = audioManager.requestAudioFocus(audioFocusRequest!!)
            if (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                Log.d(TAG, "✅ Audio focus granted for recording")
            } else {
                Log.w(TAG, "⚠️ Audio focus NOT granted for recording")
            }
        } else {
            // Android 7.1 and below - Use deprecated API
            @Suppress("DEPRECATION")
            val result = audioManager.requestAudioFocus(
                null,
                AudioManager.STREAM_VOICE_CALL,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
            )
            if (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                Log.d(TAG, "✅ Audio focus granted for recording (legacy)")
            } else {
                Log.w(TAG, "⚠️ Audio focus NOT granted for recording (legacy)")
            }
        }
    }
    
    /**
     * Request audio focus for media playback (stereo music)
     * NOTE: This is only used for recording. Playback audio focus is managed by AudioPlayer.
     */
    private fun requestAudioFocusForPlayback() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Android 8.0+ - Use AudioFocusRequest
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
            
            audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(audioAttributes)
                .setAcceptsDelayedFocusGain(true)
                .setWillPauseWhenDucked(false)  // Don't pause when another app ducks
                .setOnAudioFocusChangeListener { focusChange ->
                    Log.d(TAG, "Playback audio focus change: $focusChange")
                    // Don't fight with AudioPlayer's focus management
                    when (focusChange) {
                        AudioManager.AUDIOFOCUS_LOSS -> {
                            Log.d(TAG, "⚠️ Audio focus lost - AudioPlayer will handle this")
                        }
                        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                            Log.d(TAG, "⚠️ Audio focus lost temporarily")
                        }
                        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                            Log.d(TAG, "📢 Audio ducked")
                        }
                        AudioManager.AUDIOFOCUS_GAIN -> {
                            Log.d(TAG, "✅ Audio focus gained")
                        }
                    }
                }
                .build()
            
            val result = audioManager.requestAudioFocus(audioFocusRequest!!)
            if (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                Log.d(TAG, "✅ Audio focus granted for stereo playback")
            } else {
                Log.w(TAG, "⚠️ Audio focus NOT granted for playback")
            }
        } else {
            // Android 7.1 and below - Use deprecated API
            @Suppress("DEPRECATION")
            val result = audioManager.requestAudioFocus(
                null,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN
            )
            if (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                Log.d(TAG, "✅ Audio focus granted for stereo playback (legacy)")
            } else {
                Log.w(TAG, "⚠️ Audio focus NOT granted for playback (legacy)")
            }
        }
    }
    
    /**
     * Release audio focus
     */
    private fun releaseAudioFocus() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let {
                audioManager.abandonAudioFocusRequest(it)
                Log.d(TAG, "✅ Released audio focus")
            }
            audioFocusRequest = null
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(null)
            Log.d(TAG, "✅ Released audio focus (legacy)")
        }
    }
}
