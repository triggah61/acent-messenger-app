package com.example.acent_messenger

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Context
import android.media.AudioManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_ROUTE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
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
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        audioProfileService.cleanup()
        releaseAudioFocus()
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
