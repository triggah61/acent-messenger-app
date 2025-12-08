package com.qmessenger.app

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHeadset
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothA2dp
import android.content.Context
import android.media.AudioManager
import io.flutter.plugin.common.MethodChannel

class BluetoothAudioService(private val context: Context) {
    
    private val bluetoothAdapter: BluetoothAdapter? = BluetoothAdapter.getDefaultAdapter()
    private val audioManager: AudioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    
    private var bluetoothHeadset: BluetoothHeadset? = null
    private var bluetoothA2dp: BluetoothA2dp? = null
    private var pendingResult: MethodChannel.Result? = null
    
    /**
     * Check if a Bluetooth audio device is connected
     */
    fun checkBluetoothConnection(result: MethodChannel.Result) {
        try {
            android.util.Log.d("BluetoothAudioService", "Starting Bluetooth check...")
            
            // Check if Bluetooth is enabled
            if (bluetoothAdapter == null) {
                android.util.Log.e("BluetoothAudioService", "Bluetooth adapter is null")
                result.success(mapOf(
                    "isConnected" to false,
                    "deviceName" to "Bluetooth not available"
                ))
                return
            }
            
            if (!bluetoothAdapter.isEnabled) {
                android.util.Log.e("BluetoothAudioService", "Bluetooth is disabled")
                result.success(mapOf(
                    "isConnected" to false,
                    "deviceName" to "Bluetooth disabled"
                ))
                return
            }

            // Store pending result
            pendingResult = result
            
            // Method 1: Check via AudioManager
            val isBluetoothA2dpOn = audioManager.isBluetoothA2dpOn
            val isBluetoothScoOn = audioManager.isBluetoothScoOn
            
            android.util.Log.d("BluetoothAudioService", "AudioManager - A2DP: $isBluetoothA2dpOn, SCO: $isBluetoothScoOn")
            
            // Method 2: Check using BluetoothProfile
            try {
                bluetoothAdapter.getProfileProxy(context, object : BluetoothProfile.ServiceListener {
                    override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                        android.util.Log.d("BluetoothAudioService", "Profile connected: $profile")
                        
                        var deviceName = "No device"
                        var isProfileConnected = false
                        
                        try {
                            when (profile) {
                                BluetoothProfile.HEADSET -> {
                                    bluetoothHeadset = proxy as BluetoothHeadset
                                    val connectedDevices = bluetoothHeadset?.connectedDevices
                                    android.util.Log.d("BluetoothAudioService", "Headset connected devices: ${connectedDevices?.size ?: 0}")
                                    
                                    if (!connectedDevices.isNullOrEmpty()) {
                                        isProfileConnected = true
                                        deviceName = connectedDevices[0].name ?: "Unknown Device"
                                    }
                                }
                                BluetoothProfile.A2DP -> {
                                    bluetoothA2dp = proxy as BluetoothA2dp
                                    val connectedDevices = bluetoothA2dp?.connectedDevices
                                    android.util.Log.d("BluetoothAudioService", "A2DP connected devices: ${connectedDevices?.size ?: 0}")
                                    
                                    if (!connectedDevices.isNullOrEmpty()) {
                                        isProfileConnected = true
                                        deviceName = connectedDevices[0].name ?: "Unknown Device"
                                    }
                                }
                            }
                        } catch (e: SecurityException) {
                            android.util.Log.e("BluetoothAudioService", "Security exception: ${e.message}")
                        }
                        
                        // Return result when we have checked both profiles or found a connection
                        val isConnected = isBluetoothA2dpOn || isBluetoothScoOn || isProfileConnected
                        
                        android.util.Log.d("BluetoothAudioService", "Final result - Connected: $isConnected, Device: $deviceName")
                        
                        pendingResult?.success(mapOf(
                            "isConnected" to isConnected,
                            "deviceName" to deviceName
                        ))
                        pendingResult = null
                        
                        // Close the proxy
                        bluetoothAdapter.closeProfileProxy(profile, proxy)
                    }

                    override fun onServiceDisconnected(profile: Int) {
                        android.util.Log.d("BluetoothAudioService", "Profile disconnected: $profile")
                    }
                }, BluetoothProfile.A2DP)
                
                // Also check headset profile
                bluetoothAdapter.getProfileProxy(context, object : BluetoothProfile.ServiceListener {
                    override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                        // Already handled in A2DP callback
                    }
                    override fun onServiceDisconnected(profile: Int) {}
                }, BluetoothProfile.HEADSET)
                
            } catch (e: SecurityException) {
                android.util.Log.e("BluetoothAudioService", "Permission error: ${e.message}")
                result.success(mapOf(
                    "isConnected" to (isBluetoothA2dpOn || isBluetoothScoOn),
                    "deviceName" to if (isBluetoothA2dpOn || isBluetoothScoOn) "Connected (permission needed for name)" else "No device"
                ))
            }
            
        } catch (e: Exception) {
            android.util.Log.e("BluetoothAudioService", "Error checking Bluetooth: ${e.message}")
            e.printStackTrace()
            result.error("BLUETOOTH_ERROR", e.message, null)
        }
    }

    /**
     * Request Bluetooth permissions
     */
    fun requestPermissions(result: MethodChannel.Result) {
        result.success(bluetoothAdapter != null && bluetoothAdapter.isEnabled)
    }
}

