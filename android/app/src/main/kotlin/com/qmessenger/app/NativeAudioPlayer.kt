package com.qmessenger.app

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Native Audio Player with explicit Bluetooth A2DP routing
 * ENHANCED: Supports dual-channel simultaneous playback (left + right)
 * This bypasses Flutter's AudioPlayer to ensure proper routing to TWS
 * Production-ready with proper completion callbacks and error handling
 */
class NativeAudioPlayer(
    private val context: Context,
    private val methodChannel: MethodChannel? = null
) {
    companion object {
        private const val TAG = "NativeAudioPlayer"
    }

    // DUAL CHANNEL SUPPORT: Separate MediaPlayer instances for left and right channels
    private var mediaPlayerLeft: MediaPlayer? = null
    private var mediaPlayerRight: MediaPlayer? = null
    
    // Legacy single MediaPlayer (for backward compatibility)
    private var mediaPlayer: MediaPlayer? = null
    
    private val isPlayingLeft = AtomicBoolean(false)
    private val isPlayingRight = AtomicBoolean(false)
    private val isPreparedLeft = AtomicBoolean(false)
    private val isPreparedRight = AtomicBoolean(false)
    
    // Legacy state
    private val isPlaying = AtomicBoolean(false)
    private val isPrepared = AtomicBoolean(false)
    
    private var playbackCompletionCallback: (() -> Unit)? = null
    private var playbackStarted = false

    /**
     * Play audio file with explicit Bluetooth A2DP routing
     */
    fun playAudioFile(
        filePath: String,
        onCompletion: (() -> Unit)? = null
    ): Boolean {
        try {
            // CRITICAL: Stop any existing playback and wait for release to complete
            // This prevents MediaPlayer resource conflicts between playbacks
            stop()
            
            // CRITICAL: Wait for MediaPlayer to be fully released
            // MediaPlayer.release() is asynchronous and might not complete immediately
            // This delay prevents MEDIA_ERROR_SYSTEM on subsequent playbacks
            var releaseWaitAttempts = 0
            while (mediaPlayer != null && releaseWaitAttempts < 20) {
                Thread.sleep(50) // Wait 50ms
                releaseWaitAttempts++
            }
            
            if (mediaPlayer != null) {
                Log.w(TAG, "⚠️ MediaPlayer still exists after stop() - forcing null")
                mediaPlayer = null
            }

            playbackCompletionCallback = onCompletion
            isPlaying.set(false)
            isPrepared.set(false)
            playbackStarted = false

            Log.d(TAG, "═══ Starting Native Audio Playback (A2DP Routing) ═══")
            Log.d(TAG, "File: $filePath")
            
            // CRITICAL: Verify file exists and is fully written before proceeding
            val file = java.io.File(filePath)
            if (!file.exists()) {
                Log.e(TAG, "❌ Audio file does not exist: $filePath")
                isPlaying.set(false)
                isPrepared.set(false)
                playbackStarted = false
                methodChannel?.invokeMethod("onNativePlaybackCompleted", mapOf("error" to true))
                playbackCompletionCallback?.invoke()
                playbackCompletionCallback = null
                return false
            }
            
            val initialSize = file.length()
            Log.d(TAG, "File exists: $initialSize bytes - verifying file is ready...")
            
            // CRITICAL: Always wait minimum time to ensure file is fully flushed
            // Even if size looks stable, OS buffers might not be written to disk yet
            Log.d(TAG, "⏳ Waiting 300ms for file system flush...")
            Thread.sleep(300) // Minimum wait for file system flush
            
            // CRITICAL: Wait for file size to stabilize (file fully written and flushed)
            // FlutterTts synthesizeToFile() is asynchronous - file might still be writing
            // This prevents MEDIA_ERROR_SYSTEM during prepareAsync()
            var fileSizeStable = false
            var stabilityCheckAttempts = 0
            val maxStabilityChecks = 20 // 1 second max wait
            var lastSize = file.length()
            
            Log.d(TAG, "⏳ Checking file size stability...")
            while (!fileSizeStable && stabilityCheckAttempts < maxStabilityChecks) {
                Thread.sleep(50)
                val currentSize = file.length()
                
                if (currentSize == lastSize && currentSize > 44) { // WAV header is 44 bytes
                    // Size hasn't changed and file has content - likely stable
                    // Double-check with one more read
                    Thread.sleep(100) // Longer wait for final verification
                    val finalSize = file.length()
                    if (finalSize == currentSize) {
                        fileSizeStable = true
                        Log.d(TAG, "✅ File size stable at $finalSize bytes")
                    } else {
                        Log.d(TAG, "⏳ File size changed during verification: $currentSize → $finalSize")
                        lastSize = finalSize
                    }
                } else if (currentSize != lastSize) {
                    // File still growing
                    Log.d(TAG, "⏳ File still writing: $lastSize → $currentSize bytes")
                    lastSize = currentSize
                    stabilityCheckAttempts = 0 // Reset counter
                } else {
                    // Size same as last but less than header - file might be corrupt
                    if (currentSize <= 44) {
                        Log.w(TAG, "⚠️ File size suspiciously small: $currentSize bytes")
                    }
                }
                
                stabilityCheckAttempts++
            }
            
            if (!fileSizeStable) {
                Log.w(TAG, "⚠️ File size did not stabilize after ${maxStabilityChecks * 50}ms")
                Log.w(TAG, "⚠️ Last known size: ${file.length()} bytes - proceeding anyway...")
            }
            
            // CRITICAL: Verify file is readable by trying to open it multiple times
            // This ensures file descriptor is not locked by TTS engine
            var fileReadable = false
            var readAttempts = 0
            val maxReadAttempts = 5
            
            while (!fileReadable && readAttempts < maxReadAttempts) {
                try {
                    val fis = java.io.FileInputStream(file)
                    val headerBytes = ByteArray(44)
                    val bytesRead = fis.read(headerBytes) // Try to read WAV header
                    fis.close()
                    
                    if (bytesRead < 44) {
                        Log.e(TAG, "❌ File is too small or corrupted: only $bytesRead bytes readable")
                        Log.e(TAG, "   Expected at least 44 bytes (WAV header)")
                        isPlaying.set(false)
                        isPrepared.set(false)
                        playbackStarted = false
                        methodChannel?.invokeMethod("onNativePlaybackCompleted", mapOf("error" to true))
                        playbackCompletionCallback?.invoke()
                        playbackCompletionCallback = null
                        return false
                    }
                    
                    // Verify WAV header signature
                    val signature = String(headerBytes.sliceArray(0..3))
                    if (signature != "RIFF") {
                        Log.e(TAG, "❌ Invalid WAV file: header signature is '$signature', expected 'RIFF'")
                        isPlaying.set(false)
                        isPrepared.set(false)
                        playbackStarted = false
                        methodChannel?.invokeMethod("onNativePlaybackCompleted", mapOf("error" to true))
                        playbackCompletionCallback?.invoke()
                        playbackCompletionCallback = null
                        return false
                    }
                    
                    fileReadable = true
                    Log.d(TAG, "✅ File is readable and accessible (valid WAV format)")
                } catch (e: Exception) {
                    readAttempts++
                    if (readAttempts < maxReadAttempts) {
                        Log.w(TAG, "⚠️ File read attempt $readAttempts failed: ${e.message}")
                        Log.w(TAG, "   Retrying in 100ms...")
                        Thread.sleep(100)
                    } else {
                        Log.e(TAG, "❌ File is not readable after $maxReadAttempts attempts: ${e.message}")
                        Log.e(TAG, "   File may still be open by TTS engine or system")
                        Log.e(TAG, "   Exception type: ${e.javaClass.simpleName}")
                        isPlaying.set(false)
                        isPrepared.set(false)
                        playbackStarted = false
                        methodChannel?.invokeMethod("onNativePlaybackCompleted", mapOf("error" to true))
                        playbackCompletionCallback?.invoke()
                        playbackCompletionCallback = null
                        return false
                    }
                }
            }
            
            Log.d(TAG, "✅ File verified: ${file.length()} bytes, ready for MediaPlayer")

            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

            // CRITICAL: Create AudioAttributes for MEDIA stream (A2DP routing)
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)  // MEDIA usage → A2DP
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)  // MUSIC → A2DP
                .build()

            // Create MediaPlayer with AudioAttributes
            try {
                mediaPlayer = MediaPlayer()
                
                // CRITICAL: Set error listener FIRST (before prepareAsync)
                // This ensures we catch any errors during preparation
                mediaPlayer!!.setOnErrorListener { mp, what, extra ->
                    try {
                        // CRITICAL: Decode MediaPlayer error codes
                        val errorCode = when (what) {
                            MediaPlayer.MEDIA_ERROR_UNKNOWN -> "MEDIA_ERROR_UNKNOWN(1)"
                            MediaPlayer.MEDIA_ERROR_SERVER_DIED -> "MEDIA_ERROR_SERVER_DIED(100)"
                            MediaPlayer.MEDIA_ERROR_NOT_VALID_FOR_PROGRESSIVE_PLAYBACK -> "MEDIA_ERROR_NOT_VALID_FOR_PROGRESSIVE_PLAYBACK(200)"
                            MediaPlayer.MEDIA_ERROR_IO -> "MEDIA_ERROR_IO(-1004)"
                            MediaPlayer.MEDIA_ERROR_MALFORMED -> "MEDIA_ERROR_MALFORMED(-1007)"
                            MediaPlayer.MEDIA_ERROR_UNSUPPORTED -> "MEDIA_ERROR_UNSUPPORTED(-1010)"
                            MediaPlayer.MEDIA_ERROR_TIMED_OUT -> "MEDIA_ERROR_TIMED_OUT(-110)"
                            else -> "UNKNOWN_ERROR_CODE($what)"
                        }
                        
                        val extraCode = when (extra) {
                            MediaPlayer.MEDIA_ERROR_IO -> "MEDIA_ERROR_IO(-1004)"
                            MediaPlayer.MEDIA_ERROR_MALFORMED -> "MEDIA_ERROR_MALFORMED(-1007)"
                            MediaPlayer.MEDIA_ERROR_UNSUPPORTED -> "MEDIA_ERROR_UNSUPPORTED(-1010)"
                            MediaPlayer.MEDIA_ERROR_TIMED_OUT -> "MEDIA_ERROR_TIMED_OUT(-110)"
                            -2147483648 -> "MEDIA_ERROR_SYSTEM(-2147483648)" // System-level error
                            else -> "UNKNOWN_EXTRA($extra)"
                        }
                        
                        Log.e(TAG, "═══════════════════════════════════════════════════")
                        Log.e(TAG, "❌ CRITICAL: MediaPlayer ERROR OCCURRED")
                        Log.e(TAG, "═══════════════════════════════════════════════════")
                        Log.e(TAG, "Error Details:")
                        Log.e(TAG, "  - Error Code (what): $errorCode")
                        Log.e(TAG, "  - Extra Code: $extraCode")
                        Log.e(TAG, "  - File: $filePath")
                        Log.e(TAG, "  - File exists: ${java.io.File(filePath).exists()}")
                        Log.e(TAG, "  - File size: ${java.io.File(filePath).length()} bytes")
                        Log.e(TAG, "MediaPlayer State:")
                        Log.e(TAG, "  - Prepared: ${isPrepared.get()}")
                        Log.e(TAG, "  - Playing: ${mp.isPlaying}")
                        Log.e(TAG, "  - Playback started: $playbackStarted")
                        try {
                            Log.e(TAG, "  - Duration: ${mp.duration}ms")
                            Log.e(TAG, "  - Current position: ${mp.currentPosition}ms")
                        } catch (e: Exception) {
                            Log.e(TAG, "  - Duration/Position: unavailable (${e.message})")
                        }
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                val routedDevice = mp.routedDevice
                                Log.e(TAG, "  - Routed device: ${routedDevice?.productName ?: "none"}")
                                Log.e(TAG, "  - Device type: ${routedDevice?.type ?: "none"}")
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "  - Routed device: error (${e.message})")
                        }
                        
                        Log.e(TAG, "Error Explanation:")
                        when (what) {
                            MediaPlayer.MEDIA_ERROR_UNKNOWN -> {
                                Log.e(TAG, "  MEDIA_ERROR_UNKNOWN: Unspecified media player error")
                                if (extra == -2147483648) {
                                    Log.e(TAG, "  → System-level error during file access or preparation")
                                    Log.e(TAG, "  → Possible causes:")
                                    Log.e(TAG, "     1. File still being written by TTS engine")
                                    Log.e(TAG, "     2. File descriptor locked by another process")
                                    Log.e(TAG, "     3. Insufficient wait time after file creation")
                                    Log.e(TAG, "     4. OS buffer not flushed to disk")
                                }
                            }
                            MediaPlayer.MEDIA_ERROR_IO -> {
                                Log.e(TAG, "  MEDIA_ERROR_IO: File read/access error")
                                Log.e(TAG, "  → File may be corrupted or inaccessible")
                            }
                            MediaPlayer.MEDIA_ERROR_MALFORMED -> {
                                Log.e(TAG, "  MEDIA_ERROR_MALFORMED: Invalid file format")
                                Log.e(TAG, "  → File may not be a valid WAV file")
                            }
                            MediaPlayer.MEDIA_ERROR_UNSUPPORTED -> {
                                Log.e(TAG, "  MEDIA_ERROR_UNSUPPORTED: Unsupported audio format")
                            }
                        }
                        Log.e(TAG, "═══════════════════════════════════════════════════")
                        
                        isPlaying.set(false)
                        playbackStarted = false
                        isPrepared.set(false)
                        
                        // CRITICAL: Notify Flutter of error with details
                        methodChannel?.invokeMethod("onNativePlaybackCompleted", mapOf(
                            "error" to true,
                            "errorCode" to errorCode,
                            "extraCode" to extraCode,
                            "filePath" to filePath
                        ))
                        
                        playbackCompletionCallback?.invoke()
                        playbackCompletionCallback = null
                        true  // Error handled
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ CRITICAL: Exception in error handler: ${e.message}", e)
                        e.printStackTrace()
                        true
                    }
                }
                
                // Set AudioAttributes
                mediaPlayer!!.setAudioAttributes(audioAttributes)
                
                // CRITICAL: Set data source with error handling
                try {
                    mediaPlayer!!.setDataSource(filePath)
                    Log.d(TAG, "✅ Data source set successfully")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Failed to set data source: ${e.message}", e)
                    throw e
                }
                
                // Prepare asynchronously
                mediaPlayer!!.prepareAsync()
                Log.d(TAG, "✅ prepareAsync() called - waiting for preparation...")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to create MediaPlayer: ${e.message}", e)
                mediaPlayer?.release()
                mediaPlayer = null
                isPlaying.set(false)
                isPrepared.set(false)
                playbackStarted = false
                methodChannel?.invokeMethod("onNativePlaybackCompleted", mapOf("error" to true))
                playbackCompletionCallback?.invoke()
                playbackCompletionCallback = null
                return false
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

            // Set up listeners with proper synchronization
            mediaPlayer!!.setOnPreparedListener { mp ->
                try {
                    Log.d(TAG, "✅ MediaPlayer prepared successfully")
                    isPrepared.set(true)
                    
                    Log.d(TAG, "⏳ Waiting 200ms for A2DP/TWS device to be ready...")
                    Thread.sleep(200) // Let TWS device wake up and prepare for audio stream
                    Log.d(TAG, "✅ TWS device ready - verifying routing before playback")
                    
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
                    
                    // CRITICAL: Ensure MediaPlayer is in correct state before starting
                    if (mp.isPlaying) {
                        Log.w(TAG, "⚠️ MediaPlayer already playing - stopping first")
                        mp.stop()
                        mp.prepareAsync()
                        return@setOnPreparedListener
                    }
                    
                    // CRITICAL: Start playback and verify it actually started
                    Log.d(TAG, "Starting playback...")
                    Log.d(TAG, "  Audio duration: ${mp.duration}ms")
                    Log.d(TAG, "  Current position: ${mp.currentPosition}ms")
                    
                    mp.start()
                    
                    // Wait a moment to ensure playback actually started
                    Thread.sleep(100)
                    
                    if (mp.isPlaying) {
                        isPlaying.set(true)
                        playbackStarted = true
                        Log.d(TAG, "✅ Playback started successfully")
                        Log.d(TAG, "  isPlaying: ${mp.isPlaying}")
                        Log.d(TAG, "  Current position: ${mp.currentPosition}ms")
                        Log.d(TAG, "  Duration: ${mp.duration}ms")
                        
                        // Notify Flutter that playback has started
                        methodChannel?.invokeMethod("onNativePlaybackStarted", null)
                    } else {
                        Log.e(TAG, "❌ CRITICAL: MediaPlayer.start() called but isPlaying=false")
                        Log.e(TAG, "   This usually means playback failed to start")
                        Log.e(TAG, "   Possible causes:")
                        Log.e(TAG, "     1. Audio focus denied by system")
                        Log.e(TAG, "     2. Audio routing conflict")
                        Log.e(TAG, "     3. File corruption or invalid format")
                        Log.e(TAG, "     4. MediaPlayer in invalid state")
                        Log.e(TAG, "   MediaPlayer state:")
                        Log.e(TAG, "     - Position: ${mp.currentPosition}ms")
                        Log.e(TAG, "     - Duration: ${mp.duration}ms")
                        Log.e(TAG, "     - isPlaying: ${mp.isPlaying}")
                        try {
                            Log.e(TAG, "     - Routed device: ${mp.routedDevice?.productName ?: "unknown"}")
                        } catch (e: Exception) {
                            Log.e(TAG, "     - Routed device: error getting device info")
                        }
                        isPlaying.set(false)
                        playbackStarted = false
                        isPrepared.set(false)
                        // Notify Flutter of failure
                        methodChannel?.invokeMethod("onNativePlaybackCompleted", mapOf("error" to true))
                        playbackCompletionCallback?.invoke()
                        playbackCompletionCallback = null
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Error in onPrepared: ${e.message}", e)
                    isPlaying.set(false)
                    playbackStarted = false
                    isPrepared.set(false)
                    // Notify Flutter of error
                    methodChannel?.invokeMethod("onNativePlaybackCompleted", mapOf("error" to true))
                    playbackCompletionCallback?.invoke()
                    playbackCompletionCallback = null
                }
            }

            mediaPlayer!!.setOnCompletionListener { mp ->
                try {
                    Log.d(TAG, "✅ Playback completed naturally")
                    Log.d(TAG, "  Final position: ${mp.currentPosition}ms / ${mp.duration}ms")
                    isPlaying.set(false)
                    playbackStarted = false
                    
                    // CRITICAL: Notify Flutter immediately via method channel
                    methodChannel?.invokeMethod("onNativePlaybackCompleted", null)
                    
                    // Also call callback if provided
                    playbackCompletionCallback?.invoke()
                    playbackCompletionCallback = null
                    
                    // NOTE: Don't auto-release here - let stop() handle it
                    // Auto-release can cause issues if next playback starts immediately
                    Log.d(TAG, "✅ Completion callback sent - MediaPlayer will be released by stop()")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ CRITICAL ERROR in onCompletion: ${e.message}", e)
                    Log.e(TAG, "   Exception type: ${e.javaClass.simpleName}")
                    Log.e(TAG, "   Stack trace:")
                    e.printStackTrace()
                }
            }

            // CRITICAL: Also listen for playback info to detect interruptions
            // Note: Error listener is already set above (before prepareAsync)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                mediaPlayer!!.setOnInfoListener { mp, what, extra ->
                    when (what) {
                        MediaPlayer.MEDIA_INFO_BUFFERING_START -> {
                            Log.d(TAG, "⏳ Buffering started")
                        }
                        MediaPlayer.MEDIA_INFO_BUFFERING_END -> {
                            Log.d(TAG, "✅ Buffering ended")
                        }
                        MediaPlayer.MEDIA_INFO_AUDIO_NOT_PLAYING -> {
                            Log.w(TAG, "⚠️ Audio not playing (possible interruption)")
                            // Check if still supposed to be playing
                            if (!isPlaying.get() && playbackStarted) {
                                Log.w(TAG, "⚠️ Playback interrupted - notifying completion")
                                isPlaying.set(false)
                                methodChannel?.invokeMethod("onNativePlaybackCompleted", null)
                            }
                        }
                    }
                    true
                }
            }

            Log.d(TAG, "✅ MediaPlayer setup complete - preparation will complete asynchronously")
            
            // CRITICAL: Don't block here - return true immediately and let async preparation continue
            // The onPreparedListener will handle starting playback
            // Returning false here would cause immediate failure even if preparation succeeds later
            
            // Start a background check for preparation timeout (non-blocking)
            Thread {
                val prepared = waitForPreparation(8000) // 8 second timeout (generous for file I/O)
                if (!prepared) {
                    Log.e(TAG, "❌ MediaPlayer preparation timeout (8s) - playback may fail")
                    Log.e(TAG, "   File may be corrupted or MediaPlayer may be stuck")
                    Log.e(TAG, "   File: $filePath")
                    // Don't return false - let error listener handle it
                    // Error listener will notify Flutter if preparation fails
                } else {
                    Log.d(TAG, "✅ MediaPlayer prepared successfully within timeout")
                }
            }.start()
            
            return true

        } catch (e: IOException) {
            Log.e(TAG, "❌ Error setting up MediaPlayer: ${e.message}", e)
            isPlaying.set(false)
            isPrepared.set(false)
            playbackStarted = false
            methodChannel?.invokeMethod("onNativePlaybackCompleted", mapOf("error" to true))
            playbackCompletionCallback?.invoke()
            playbackCompletionCallback = null
            return false
        } catch (e: Exception) {
            Log.e(TAG, "❌ Unexpected error: ${e.message}", e)
            isPlaying.set(false)
            isPrepared.set(false)
            playbackStarted = false
            methodChannel?.invokeMethod("onNativePlaybackCompleted", mapOf("error" to true))
            playbackCompletionCallback?.invoke()
            playbackCompletionCallback = null
            return false
        }
    }

    /**
     * DUAL CHANNEL SUPPORT: Play audio file on specific channel (left or right)
     * Enables simultaneous playback on both channels for true parallel translation
     */
    fun playAudioFileOnChannel(
        filePath: String,
        channel: String,
        onCompletion: (() -> Unit)? = null
    ): Boolean {
        try {
            val isLeftChannel = (channel == "left")
            val TAG_CHANNEL = if (isLeftChannel) "$TAG-LEFT" else "$TAG-RIGHT"
            
            Log.d(TAG_CHANNEL, "═══ Starting Dual-Channel Playback ═══")
            Log.d(TAG_CHANNEL, "File: $filePath")
            Log.d(TAG_CHANNEL, "Channel: $channel")
            
            // CRITICAL: Stop any existing playback on this channel
            stopChannel(channel)
            var releaseWaitAttempts = 0
            val targetPlayer = if (isLeftChannel) mediaPlayerLeft else mediaPlayerRight
            while (targetPlayer != null && releaseWaitAttempts < 20) {
                Thread.sleep(50)
                releaseWaitAttempts++
            }
            
            if (isLeftChannel) {
                if (mediaPlayerLeft != null) {
                    Log.w(TAG_CHANNEL, "⚠️ MediaPlayer still exists - forcing null")
                    mediaPlayerLeft = null
                }
                isPlayingLeft.set(false)
                isPreparedLeft.set(false)
            } else {
                if (mediaPlayerRight != null) {
                    Log.w(TAG_CHANNEL, "⚠️ MediaPlayer still exists - forcing null")
                    mediaPlayerRight = null
                }
                isPlayingRight.set(false)
                isPreparedRight.set(false)
            }

            // Verify file exists
            val file = java.io.File(filePath)
            if (!file.exists()) {
                Log.e(TAG_CHANNEL, "❌ File does not exist: $filePath")
                methodChannel?.invokeMethod(
                    if (isLeftChannel) "onNativePlaybackCompletedLeft" else "onNativePlaybackCompletedRight",
                    mapOf("error" to true)
                )
                onCompletion?.invoke()
                return false
            }

            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

            // Create AudioAttributes for A2DP routing
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()

            // Create new MediaPlayer
            val player = MediaPlayer()
            
            if (isLeftChannel) {
                mediaPlayerLeft = player
            } else {
                mediaPlayerRight = player
            }
            
            player.setAudioAttributes(audioAttributes)
            player.setDataSource(filePath)

            // Set up completion listener
            player.setOnCompletionListener { mp ->
                Log.d(TAG_CHANNEL, "✅ Playback completed")
                
                if (isLeftChannel) {
                    isPlayingLeft.set(false)
                    isPreparedLeft.set(false)
                } else {
                    isPlayingRight.set(false)
                    isPreparedRight.set(false)
                }
                
                methodChannel?.invokeMethod(
                    if (isLeftChannel) "onNativePlaybackCompletedLeft" else "onNativePlaybackCompletedRight",
                    null
                )
                onCompletion?.invoke()
                
                try {
                    mp.release()
                    if (isLeftChannel) {
                        mediaPlayerLeft = null
                    } else {
                        mediaPlayerRight = null
                    }
                } catch (e: Exception) {
                    Log.w(TAG_CHANNEL, "Error releasing: ${e.message}")
                }
            }

            // Set up error listener
            player.setOnErrorListener { mp, what, extra ->
                Log.e(TAG_CHANNEL, "❌ Error: what=$what, extra=$extra")
                
                if (isLeftChannel) {
                    isPlayingLeft.set(false)
                    isPreparedLeft.set(false)
                } else {
                    isPlayingRight.set(false)
                    isPreparedRight.set(false)
                }
                
                methodChannel?.invokeMethod(
                    if (isLeftChannel) "onNativePlaybackCompletedLeft" else "onNativePlaybackCompletedRight",
                    mapOf("error" to true)
                )
                onCompletion?.invoke()
                
                try {
                    mp.release()
                    if (isLeftChannel) {
                        mediaPlayerLeft = null
                    } else {
                        mediaPlayerRight = null
                    }
                } catch (e: Exception) {}
                
                true
            }

            // Set up prepared listener
            player.setOnPreparedListener { mp ->
                Log.d(TAG_CHANNEL, "✅ Prepared - starting playback")
                
                if (isLeftChannel) {
                    isPreparedLeft.set(true)
                } else {
                    isPreparedRight.set(true)
                }
                
                // Force A2DP routing
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                    for (device in devices) {
                        if (device.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP) {
                            mp.setPreferredDevice(device)
                            Log.d(TAG_CHANNEL, "✅ A2DP routing set: ${device.productName}")
                            break
                        }
                    }
                }
                
                Log.d(TAG_CHANNEL, "Starting playback...")
                mp.start()
                Thread.sleep(100)
                
                if (mp.isPlaying) {
                    if (isLeftChannel) {
                        isPlayingLeft.set(true)
                    } else {
                        isPlayingRight.set(true)
                    }
                    Log.d(TAG_CHANNEL, "✅ Playback started")
                    methodChannel?.invokeMethod(
                        if (isLeftChannel) "onNativePlaybackStartedLeft" else "onNativePlaybackStartedRight",
                        null
                    )
                }
            }

            player.prepareAsync()
            Log.d(TAG_CHANNEL, "✅ Dual-channel playback initiated")
            return true
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in dual-channel playback: ${e.message}")
            e.printStackTrace()
            return false
        }
    }

    /**
     * Stop playback on specific channel
     */
    fun stopChannel(channel: String) {
        try {
            val isLeftChannel = (channel == "left")
            val player = if (isLeftChannel) mediaPlayerLeft else mediaPlayerRight
            
            if (player != null) {
                try {
                    if (player.isPlaying) {
                        player.stop()
                    }
                    player.release()
                } catch (e: Exception) {
                    Log.w(TAG, "Error stopping channel: ${e.message}")
                }
                
                if (isLeftChannel) {
                    mediaPlayerLeft = null
                    isPlayingLeft.set(false)
                    isPreparedLeft.set(false)
                } else {
                    mediaPlayerRight = null
                    isPlayingRight.set(false)
                    isPreparedRight.set(false)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error in stopChannel: ${e.message}")
        }
    }

    /**
     * Stop playback and release MediaPlayer resources (all channels)
     * CRITICAL: This must complete before creating a new MediaPlayer instance
     */
    fun stop() {
        try {
            // Stop legacy player
            val mp = mediaPlayer
            if (mp != null) {
                try {
                    val wasPlaying = isPlaying.get()
                    if (wasPlaying) {
                        try {
                            mp.stop()
                            Log.d(TAG, "✅ Playback stopped")
                        } catch (e: Exception) {
                            Log.w(TAG, "⚠️ Error stopping playback: ${e.message}")
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "⚠️ Error checking playback state: ${e.message}")
                }
                
                try {
                    mp.setOnPreparedListener(null)
                    mp.setOnCompletionListener(null)
                    mp.setOnErrorListener(null)
                    mp.setOnInfoListener(null)
                } catch (e: Exception) {
                    Log.w(TAG, "⚠️ Error clearing listeners: ${e.message}")
                }
                
                try {
                    mp.release()
                    Log.d(TAG, "✅ MediaPlayer released")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Error releasing MediaPlayer: ${e.message}", e)
                }
                
                mediaPlayer = null
                isPlaying.set(false)
                isPrepared.set(false)
                playbackStarted = false
            }
            
            // Stop dual-channel players
            stopChannel("left")
            stopChannel("right")
            
            playbackCompletionCallback = null
            Log.d(TAG, "✅ Stop complete - all MediaPlayers cleared")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in stop(): ${e.message}", e)
            // Force cleanup
            mediaPlayer = null
            mediaPlayerLeft = null
            mediaPlayerRight = null
            isPlaying.set(false)
            isPrepared.set(false)
            isPlayingLeft.set(false)
            isPreparedLeft.set(false)
            isPlayingRight.set(false)
            isPreparedRight.set(false)
            playbackStarted = false
            playbackCompletionCallback = null
        }
    }

    /**
     * Check if currently playing - production-ready with multiple checks
     */
    fun isCurrentlyPlaying(): Boolean {
        return try {
            val mp = mediaPlayer
            if (mp == null) {
                false
            } else {
                // CRITICAL: Multiple checks to ensure accuracy
                val playingState = isPlaying.get() && mp.isPlaying
                
                // If state says playing but MediaPlayer says not, update state
                if (isPlaying.get() && !mp.isPlaying && playbackStarted) {
                    Log.w(TAG, "⚠️ State mismatch: isPlaying=true but MediaPlayer.isPlaying=false")
                    isPlaying.set(false)
                    // Notify completion if playback was interrupted
                    methodChannel?.invokeMethod("onNativePlaybackCompleted", null)
                    return false
                }
                
                playingState
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking playback state: ${e.message}")
            false
        }
    }
    
    /**
     * Wait for preparation to complete
     */
    fun waitForPreparation(timeoutMs: Long = 5000): Boolean {
        val startTime = System.currentTimeMillis()
        while (!isPrepared.get() && (System.currentTimeMillis() - startTime) < timeoutMs) {
            Thread.sleep(50)
        }
        return isPrepared.get()
    }

    /**
     * Release resources
     */
    fun release() {
        stop()
    }
}

