package com.example.acent_messenger

import android.content.Context
import android.media.AudioManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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

        // Audio route channel: force phone mic
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_ROUTE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "forcePhoneMic" -> {
                    try {
                        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        try { am.stopBluetoothSco() } catch (_: Exception) {}
                        am.isBluetoothScoOn = false
                        am.mode = AudioManager.MODE_IN_COMMUNICATION
                        am.isSpeakerphoneOn = true
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("AUDIO_ROUTE", e.message, null)
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
