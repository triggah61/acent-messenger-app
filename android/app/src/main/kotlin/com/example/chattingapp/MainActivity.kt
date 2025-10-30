package com.example.acent_messenger

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Context
import android.media.AudioManager
import android.os.Build

class MainActivity : FlutterActivity() {
    private val BLUETOOTH_CHANNEL = "bluetooth_audio_service"
    private val AUDIO_PROFILE_CHANNEL = "audio_profile_service"
    private val AUDIO_ROUTE_CHANNEL = "audio_route"
    
    private lateinit var bluetoothService: BluetoothAudioService
    private lateinit var audioProfileService: AudioProfileService

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
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        try { audioManager.stopBluetoothSco() } catch (_: Exception) {}
                        try { audioManager.isBluetoothScoOn = false } catch (_: Exception) {}
                        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                        try { audioManager.isSpeakerphoneOn = false } catch (_: Exception) {}
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("AUDIO_ROUTE_ERROR", e.message, null)
                    }
                }
                "enterPlaybackRoute" -> {
                    try {
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        // Use normal mode so media routes to A2DP if available
                        audioManager.mode = AudioManager.MODE_NORMAL
                        try { audioManager.isBluetoothScoOn = false } catch (_: Exception) {}
                        try { audioManager.stopBluetoothSco() } catch (_: Exception) {}
                        try { audioManager.isSpeakerphoneOn = false } catch (_: Exception) {}
                        result.success(true)
                    } catch (e: Exception) {
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
    }
}
