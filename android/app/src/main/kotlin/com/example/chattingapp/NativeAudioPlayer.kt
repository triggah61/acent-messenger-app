package com.example.acent_messenger

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.util.Log
import java.io.IOException

/**
 * Native Audio Player with explicit Bluetooth A2DP routing
 * This bypasses Flutter's AudioPlayer to ensure proper routing to TWS
 */
class NativeAudioPlayer(private val context: Context) {
    companion object {
        private const val TAG = "NativeAudioPlayer"
    }

    private var mediaPlayer: MediaPlayer? = null
    private var isPlaying = false
    private var playbackCompletionCallback: (() -> Unit)? = null

    /**
     * Play audio file with explicit Bluetooth A2DP routing
     */
    fun playAudioFile(
        filePath: String,
        onCompletion: (() -> Unit)? = null
    ): Boolean {
        try {
            // Stop any existing playback
            stop()

            playbackCompletionCallback = onCompletion
            isPlaying = false

            Log.d(TAG, "═══ Starting Native Audio Playback (A2DP Routing) ═══")
            Log.d(TAG, "File: $filePath")

            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

            // CRITICAL: Create AudioAttributes for MEDIA stream (A2DP routing)
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)  // MEDIA usage → A2DP
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)  // MUSIC → A2DP
                .build()

            // Create MediaPlayer with AudioAttributes
            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(audioAttributes)
                
                // Set data source
                setDataSource(filePath)
                
                // Prepare asynchronously
                prepareAsync()
            }

            // CRITICAL: Set preferred device to Bluetooth A2DP (Android 6.0+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                try {
                    val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                    val bluetoothA2dpDevice = devices.find { 
                        it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP 
                    }
                    
                    if (bluetoothA2dpDevice != null) {
                        Log.d(TAG, "✅ Found Bluetooth A2DP device: ${bluetoothA2dpDevice.productName}")
                        
                        // CRITICAL: Set preferred device for MediaPlayer
                        val success = mediaPlayer!!.setPreferredDevice(bluetoothA2dpDevice)
                        if (success) {
                            Log.d(TAG, "✅ Successfully set preferred device to Bluetooth A2DP")
                            Log.d(TAG, "   Device: ${bluetoothA2dpDevice.productName}")
                        } else {
                            Log.w(TAG, "⚠️ Failed to set preferred device (may still work)")
                        }
                    } else {
                        Log.w(TAG, "⚠️ No Bluetooth A2DP device found")
                        Log.w(TAG, "   Audio may route to phone speaker")
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "⚠️ Could not set preferred device: ${e.message}")
                }
            } else {
                Log.d(TAG, "Android < 6.0 - Cannot set preferred device")
                Log.d(TAG, "   Relying on AudioAttributes routing")
            }

            // Set up listeners
            mediaPlayer!!.setOnPreparedListener { mp ->
                Log.d(TAG, "✅ MediaPlayer prepared - starting playback")
                
                // CRITICAL: Double-check routing before starting
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    val routing = mp.routedDevice
                    if (routing != null) {
                        Log.d(TAG, "Routing device: ${routing.productName} (Type: ${routing.type})")
                        if (routing.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP) {
                            Log.d(TAG, "✅ Routing confirmed: Bluetooth A2DP")
                        } else {
                            Log.w(TAG, "⚠️ Routing may not be A2DP (Type: ${routing.type})")
                            Log.w(TAG, "   Audio might play through phone speaker")
                        }
                    } else {
                        Log.w(TAG, "⚠️ No routing device info available")
                    }
                }
                
                mp.start()
                isPlaying = true
                Log.d(TAG, "✅ Playback started")
            }

            mediaPlayer!!.setOnCompletionListener { mp ->
                Log.d(TAG, "✅ Playback completed")
                isPlaying = false
                playbackCompletionCallback?.invoke()
                playbackCompletionCallback = null
            }

            mediaPlayer!!.setOnErrorListener { mp, what, extra ->
                Log.e(TAG, "❌ MediaPlayer error: what=$what, extra=$extra")
                isPlaying = false
                playbackCompletionCallback?.invoke()  // Still notify completion
                playbackCompletionCallback = null
                true  // Error handled
            }

            Log.d(TAG, "✅ MediaPlayer setup complete - waiting for preparation")
            return true

        } catch (e: IOException) {
            Log.e(TAG, "❌ Error setting up MediaPlayer: ${e.message}", e)
            isPlaying = false
            playbackCompletionCallback?.invoke()
            playbackCompletionCallback = null
            return false
        } catch (e: Exception) {
            Log.e(TAG, "❌ Unexpected error: ${e.message}", e)
            isPlaying = false
            playbackCompletionCallback?.invoke()
            playbackCompletionCallback = null
            return false
        }
    }

    /**
     * Stop playback
     */
    fun stop() {
        try {
            mediaPlayer?.let { mp ->
                if (isPlaying) {
                    mp.stop()
                    Log.d(TAG, "✅ Playback stopped")
                }
                mp.release()
                mediaPlayer = null
                isPlaying = false
            }
            playbackCompletionCallback = null
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping playback: ${e.message}")
        }
    }

    /**
     * Check if currently playing
     */
    fun isCurrentlyPlaying(): Boolean {
        return isPlaying && mediaPlayer?.isPlaying == true
    }

    /**
     * Release resources
     */
    fun release() {
        stop()
    }
}

