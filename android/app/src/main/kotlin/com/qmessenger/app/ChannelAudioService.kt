package com.qmessenger.app

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class ChannelAudioService {
    companion object {
        private const val TAG = "ChannelAudioService"
        private const val SAMPLE_RATE = 44100
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_OUT_STEREO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
    }

    private var leftAudioTrack: AudioTrack? = null
    private var rightAudioTrack: AudioTrack? = null
    private var isPlayingLeft = false
    private var isPlayingRight = false

    fun playLeftChannel(filePath: String, result: MethodChannel.Result) {
        try {
            Log.d(TAG, "Playing LEFT channel: $filePath")
            
            // Stop any existing left playback
            stopLeftChannel()
            
            // Create LEFT-only AudioTrack (LEFT channel only, RIGHT muted)
            leftAudioTrack = createChannelAudioTrack(true) // true = left only
            leftAudioTrack?.play()
            
            // Start playback in background thread
            Thread {
                try {
                    playAudioFile(filePath, leftAudioTrack, true)
                    result.success(true)
                } catch (e: Exception) {
                    Log.e(TAG, "Error playing left channel: ${e.message}")
                    result.error("PLAY_ERROR", e.message, null)
                }
            }.start()
            
        } catch (e: Exception) {
            Log.e(TAG, "Error setting up left channel: ${e.message}")
            result.error("SETUP_ERROR", e.message, null)
        }
    }

    fun playRightChannel(filePath: String, result: MethodChannel.Result) {
        try {
            Log.d(TAG, "Playing RIGHT channel: $filePath")
            
            // Stop any existing right playback
            stopRightChannel()
            
            // Create RIGHT-only AudioTrack (RIGHT channel only, LEFT muted)
            rightAudioTrack = createChannelAudioTrack(false) // false = right only
            rightAudioTrack?.play()
            
            // Start playback in background thread
            Thread {
                try {
                    playAudioFile(filePath, rightAudioTrack, false)
                    result.success(true)
                } catch (e: Exception) {
                    Log.e(TAG, "Error playing right channel: ${e.message}")
                    result.error("PLAY_ERROR", e.message, null)
                }
            }.start()
            
        } catch (e: Exception) {
            Log.e(TAG, "Error setting up right channel: ${e.message}")
            result.error("SETUP_ERROR", e.message, null)
        }
    }

    private fun createChannelAudioTrack(leftChannel: Boolean): AudioTrack {
        val bufferSize = AudioTrack.getMinBufferSize(
            SAMPLE_RATE,
            CHANNEL_CONFIG,
            AUDIO_FORMAT
        ) * 2

        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()

        val audioFormat = AudioFormat.Builder()
            .setSampleRate(SAMPLE_RATE)
            .setEncoding(AUDIO_FORMAT)
            .setChannelMask(CHANNEL_CONFIG)
            .build()

        return AudioTrack.Builder()
            .setAudioAttributes(audioAttributes)
            .setAudioFormat(audioFormat)
            .setBufferSizeInBytes(bufferSize)
            .build()
    }

    private fun playAudioFile(filePath: String, audioTrack: AudioTrack?, leftChannel: Boolean) {
        if (audioTrack == null) return

        try {
            val file = File(filePath)
            if (!file.exists()) {
                Log.e(TAG, "Audio file does not exist: $filePath")
                return
            }

            val fileInputStream = FileInputStream(file)
            val buffer = ByteArray(4096)

            // Skip WAV header (44 bytes)
            fileInputStream.skip(44)

            var bytesRead: Int
            while (fileInputStream.read(buffer).also { bytesRead = it } != -1) {
                if (leftChannel) {
                    isPlayingLeft = true
                } else {
                    isPlayingRight = true
                }

                // Process stereo audio data
                val processedBuffer = processStereoToChannel(buffer, leftChannel)
                audioTrack.write(processedBuffer, 0, processedBuffer.size)
            }

            fileInputStream.close()
            
            // Mark as stopped
            if (leftChannel) {
                isPlayingLeft = false
            } else {
                isPlayingRight = false
            }
            
            Log.d(TAG, "Finished playing ${if (leftChannel) "LEFT" else "RIGHT"} channel")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error during playback: ${e.message}")
            if (leftChannel) {
                isPlayingLeft = false
            } else {
                isPlayingRight = false
            }
        }
    }

    private fun processStereoToChannel(stereoData: ByteArray, leftChannel: Boolean): ByteArray {
        // For 16-bit stereo audio:
        // Each sample is 2 bytes, so each frame is 4 bytes (2 bytes left + 2 bytes right)
        // We need to extract only the desired channel and create a stereo output
        
        val numSamples = stereoData.size / 4 // 4 bytes per frame (left + right)
        val outputBuffer = ByteArray(stereoData.size) // Same size for stereo output
        
        for (i in 0 until numSamples) {
            val frameOffset = i * 4
            
            if (leftChannel) {
                // Extract LEFT channel and put it in both stereo channels (or just left)
                val leftSample1 = stereoData[frameOffset]
                val leftSample2 = stereoData[frameOffset + 1]
                
                // Put LEFT channel data in LEFT output
                outputBuffer[frameOffset] = leftSample1
                outputBuffer[frameOffset + 1] = leftSample2
                
                // Put silence (0) in RIGHT output
                outputBuffer[frameOffset + 2] = 0
                outputBuffer[frameOffset + 3] = 0
                
            } else {
                // Extract RIGHT channel and put it in both stereo channels (or just right)
                val rightSample1 = stereoData[frameOffset + 2]
                val rightSample2 = stereoData[frameOffset + 3]
                
                // Put silence (0) in LEFT output
                outputBuffer[frameOffset] = 0
                outputBuffer[frameOffset + 1] = 0
                
                // Put RIGHT channel data in RIGHT output
                outputBuffer[frameOffset + 2] = rightSample1
                outputBuffer[frameOffset + 3] = rightSample2
            }
        }
        
        return outputBuffer
    }

    fun stopLeftChannel() {
        try {
            if (isPlayingLeft && leftAudioTrack != null) {
                leftAudioTrack?.stop()
                leftAudioTrack?.release()
                leftAudioTrack = null
                isPlayingLeft = false
                Log.d(TAG, "Stopped LEFT channel")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping left channel: ${e.message}")
        }
    }

    fun stopRightChannel() {
        try {
            if (isPlayingRight && rightAudioTrack != null) {
                rightAudioTrack?.stop()
                rightAudioTrack?.release()
                rightAudioTrack = null
                isPlayingRight = false
                Log.d(TAG, "Stopped RIGHT channel")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping right channel: ${e.message}")
        }
    }

    fun stopAllChannels() {
        stopLeftChannel()
        stopRightChannel()
        Log.d(TAG, "Stopped all channels")
    }

    fun isLeftChannelPlaying(): Boolean = isPlayingLeft
    fun isRightChannelPlaying(): Boolean = isPlayingRight

    fun cleanup() {
        stopAllChannels()
    }
}
