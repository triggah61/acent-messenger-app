package com.qmessenger.app

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothHeadset
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.core.app.ActivityCompat
import io.flutter.plugin.common.MethodChannel

class AudioProfileService(private val context: Context) {

    private val audioManager: AudioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val bluetoothAdapter: BluetoothAdapter? = BluetoothAdapter.getDefaultAdapter()
    
    private var bluetoothHeadset: BluetoothHeadset? = null
    private var isBluetoothScoConnected = false

    /**
     * Initialize audio profile service
     */
    fun initialize(result: MethodChannel.Result) {
        try {
            android.util.Log.d("AudioProfileService", "Initializing audio profiles...")
            
            // Check Bluetooth availability
            if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled) {
                android.util.Log.w("AudioProfileService", "Bluetooth not available")
                result.success(false)
                return
            }

            // Setup Bluetooth headset profile listener
            bluetoothAdapter.getProfileProxy(context, object : BluetoothProfile.ServiceListener {
                override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                    if (profile == BluetoothProfile.HEADSET) {
                        bluetoothHeadset = proxy as BluetoothHeadset
                        android.util.Log.d("AudioProfileService", "Bluetooth headset profile connected")
                    }
                }

                override fun onServiceDisconnected(profile: Int) {
                    if (profile == BluetoothProfile.HEADSET) {
                        bluetoothHeadset = null
                        android.util.Log.d("AudioProfileService", "Bluetooth headset profile disconnected")
                    }
                }
            }, BluetoothProfile.HEADSET)

            android.util.Log.d("AudioProfileService", "Audio profile service initialized")
            result.success(true)
            
        } catch (e: Exception) {
            android.util.Log.e("AudioProfileService", "Initialization error: ${e.message}")
            result.error("INIT_ERROR", e.message, null)
        }
    }

    /**
     * Set audio profile for alternating translator
     */
    fun setAudioProfile(result: MethodChannel.Result, profile: String) {
        try {
            android.util.Log.d("AudioProfileService", "Setting audio profile: $profile")
            
            when (profile) {
                "phoneMicBluetoothSpeaker" -> {
                    // Profile A: Phone Mic → Bluetooth Speaker
                    setPhoneMicBluetoothSpeaker()
                    result.success(true)
                }
                "bluetoothMicPhoneSpeaker" -> {
                    // Profile B: Bluetooth Mic → Phone Speaker  
                    setBluetoothMicPhoneSpeaker()
                    result.success(true)
                }
                else -> {
                    android.util.Log.e("AudioProfileService", "Unknown profile: $profile")
                    result.error("INVALID_PROFILE", "Unknown audio profile: $profile", null)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("AudioProfileService", "Error setting audio profile: ${e.message}")
            result.error("PROFILE_ERROR", e.message, null)
        }
    }

    /**
     * Profile A: Phone Microphone → Bluetooth Speaker
     */
    private fun setPhoneMicBluetoothSpeaker() {
        try {
            android.util.Log.d("AudioProfileService", "Configuring: Phone Mic → Bluetooth Speaker")
            
            // Route microphone input to phone's built-in mic
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            audioManager.setBluetoothScoOn(false)  // Use phone mic
            audioManager.stopBluetoothSco()
            
            // Route speaker output to Bluetooth
            audioManager.isSpeakerphoneOn = false  // Don't use phone speaker
            audioManager.isBluetoothA2dpOn = true  // Use Bluetooth for output
            
            // Ensure Bluetooth SCO is available for output
            if (bluetoothHeadset != null && bluetoothAdapter != null) {
                if (ActivityCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED || Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                    val connectedDevices = bluetoothHeadset!!.connectedDevices
                    if (connectedDevices.isNotEmpty()) {
                        val device = connectedDevices[0]
                        bluetoothHeadset!!.startVoiceRecognition(device)
                        isBluetoothScoConnected = true
                        android.util.Log.d("AudioProfileService", "Bluetooth SCO started for output")
                    }
                }
            }
            
            android.util.Log.d("AudioProfileService", "Phone Mic → Bluetooth Speaker configured")
        } catch (e: Exception) {
            android.util.Log.e("AudioProfileService", "Error configuring Phone Mic → Bluetooth Speaker: ${e.message}")
            throw e
        }
    }

    /**
     * Profile B: Bluetooth Microphone → Phone Speaker
     */
    private fun setBluetoothMicPhoneSpeaker() {
        try {
            android.util.Log.d("AudioProfileService", "Configuring: Bluetooth Mic → Phone Speaker")
            
            // Route microphone input to Bluetooth
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            audioManager.setBluetoothScoOn(true)   // Use Bluetooth mic
            audioManager.startBluetoothSco()
            
            // Route speaker output to phone
            audioManager.isSpeakerphoneOn = true   // Use phone speaker
            audioManager.isBluetoothA2dpOn = false // Don't use Bluetooth for output
            
            // Ensure Bluetooth SCO is connected for input
            if (bluetoothHeadset != null && bluetoothAdapter != null) {
                if (ActivityCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED || Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                    val connectedDevices = bluetoothHeadset!!.connectedDevices
                    if (connectedDevices.isNotEmpty()) {
                        val device = connectedDevices[0]
                        if (!isBluetoothScoConnected) {
                            bluetoothHeadset!!.startVoiceRecognition(device)
                            isBluetoothScoConnected = true
                            android.util.Log.d("AudioProfileService", "Bluetooth SCO started for input")
                        }
                    }
                }
            }
            
            android.util.Log.d("AudioProfileService", "Bluetooth Mic → Phone Speaker configured")
        } catch (e: Exception) {
            android.util.Log.e("AudioProfileService", "Error configuring Bluetooth Mic → Phone Speaker: ${e.message}")
            throw e
        }
    }

    /**
     * Check if Bluetooth is available
     */
    fun isBluetoothAvailable(result: MethodChannel.Result) {
        try {
            val isAvailable = bluetoothAdapter != null && 
                             bluetoothAdapter.isEnabled && 
                             audioManager.isBluetoothA2dpOn
            
            android.util.Log.d("AudioProfileService", "Bluetooth available: $isAvailable")
            result.success(isAvailable)
        } catch (e: Exception) {
            android.util.Log.e("AudioProfileService", "Error checking Bluetooth availability: ${e.message}")
            result.success(false)
        }
    }

    /**
     * Get current audio profile status
     */
    fun getCurrentProfileStatus(result: MethodChannel.Result) {
        try {
            val status = mapOf(
                "isBluetoothScoOn" to audioManager.isBluetoothScoOn,
                "isBluetoothA2dpOn" to audioManager.isBluetoothA2dpOn,
                "isSpeakerphoneOn" to audioManager.isSpeakerphoneOn,
                "audioMode" to audioManager.mode,
                "isBluetoothScoConnected" to isBluetoothScoConnected
            )
            
            android.util.Log.d("AudioProfileService", "Current profile status: $status")
            result.success(status)
        } catch (e: Exception) {
            android.util.Log.e("AudioProfileService", "Error getting profile status: ${e.message}")
            result.error("STATUS_ERROR", e.message, null)
        }
    }

    /**
     * Clean up resources
     */
    fun cleanup() {
        try {
            if (isBluetoothScoConnected) {
                audioManager.stopBluetoothSco()
                audioManager.setBluetoothScoOn(false)
                isBluetoothScoConnected = false
                android.util.Log.d("AudioProfileService", "Bluetooth SCO stopped")
            }
            
            if (bluetoothAdapter != null) {
                bluetoothAdapter.closeProfileProxy(BluetoothProfile.HEADSET, bluetoothHeadset)
            }
            
            android.util.Log.d("AudioProfileService", "Audio profile service cleaned up")
        } catch (e: Exception) {
            android.util.Log.e("AudioProfileService", "Error during cleanup: ${e.message}")
        }
    }
}
