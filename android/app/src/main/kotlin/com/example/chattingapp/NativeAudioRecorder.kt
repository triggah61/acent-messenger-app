package com.example.acent_messenger

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import kotlin.concurrent.thread

/**
 * Native Audio Recorder that forces use of built-in microphone (MIC audio source)
 * This bypasses Bluetooth SCO/HFP microphone and uses the phone's internal mic only
 */
class NativeAudioRecorder(private val context: Context) {
    private val TAG = "NativeAudioRecorder"
    
    private var audioRecord: AudioRecord? = null
    private var isRecording = false
    private var recordingThread: Thread? = null
    private var outputFile: File? = null
    
    // Audio configuration
    private val sampleRate = 16000
    private val channelConfig = AudioFormat.CHANNEL_IN_MONO
    private val audioFormat = AudioFormat.ENCODING_PCM_16BIT
    private val bufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat) * 2
    
    /**
     * Start recording with forced built-in microphone
     */
    fun startRecording(filePath: String): Boolean {
        try {
            Log.d(TAG, "═══ Starting Native Audio Recording ═══")
            Log.d(TAG, "Output path: $filePath")
            
            // Stop any existing recording
            stopRecording()
            
            // Create output file
            outputFile = File(filePath)
            outputFile?.parentFile?.mkdirs()
            
            // CRITICAL: Use MIC audio source (not DEFAULT, not VOICE_COMMUNICATION)
            // This forces the built-in phone microphone regardless of Bluetooth connection
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,  // FORCE built-in mic
                sampleRate,
                channelConfig,
                audioFormat,
                bufferSize
            )
            
            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                Log.e(TAG, "❌ AudioRecord initialization failed")
                return false
            }
            
            // Start recording
            audioRecord?.startRecording()
            isRecording = true
            
            Log.d(TAG, "✅ AudioRecord initialized:")
            Log.d(TAG, "   - Audio Source: MIC (built-in microphone)")
            Log.d(TAG, "   - Sample Rate: $sampleRate Hz")
            Log.d(TAG, "   - Channel Config: MONO")
            Log.d(TAG, "   - Audio Format: PCM_16BIT")
            Log.d(TAG, "   - Buffer Size: $bufferSize bytes")
            
            // Start recording thread
            recordingThread = thread {
                writeAudioDataToFile()
            }
            
            Log.d(TAG, "✅ Native recording started successfully")
            return true
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to start recording: ${e.message}", e)
            return false
        }
    }
    
    /**
     * Stop recording
     */
    fun stopRecording(): Boolean {
        try {
            Log.d(TAG, "Stopping native audio recording...")
            
            isRecording = false
            
            audioRecord?.apply {
                if (state == AudioRecord.STATE_INITIALIZED) {
                    stop()
                    Log.d(TAG, "✅ AudioRecord stopped")
                }
                release()
                Log.d(TAG, "✅ AudioRecord released")
            }
            audioRecord = null
            
            recordingThread?.join(1000)
            recordingThread = null
            
            // Add WAV header
            outputFile?.let { file ->
                if (file.exists()) {
                    addWavHeader(file)
                    Log.d(TAG, "✅ WAV header added")
                    Log.d(TAG, "✅ Recording saved: ${file.absolutePath}")
                    Log.d(TAG, "   File size: ${file.length()} bytes")
                }
            }
            
            return true
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to stop recording: ${e.message}", e)
            return false
        }
    }
    
    /**
     * Write audio data to file
     */
    private fun writeAudioDataToFile() {
        val buffer = ByteArray(bufferSize)
        var outputStream: FileOutputStream? = null
        
        try {
            outputStream = FileOutputStream(outputFile)
            Log.d(TAG, "Recording thread started, writing audio data...")
            
            var bytesRead = 0
            while (isRecording) {
                val read = audioRecord?.read(buffer, 0, buffer.size) ?: 0
                
                if (read > 0) {
                    outputStream.write(buffer, 0, read)
                    bytesRead += read
                } else if (read == AudioRecord.ERROR_INVALID_OPERATION) {
                    Log.e(TAG, "❌ AudioRecord error: INVALID_OPERATION")
                    break
                } else if (read == AudioRecord.ERROR_BAD_VALUE) {
                    Log.e(TAG, "❌ AudioRecord error: BAD_VALUE")
                    break
                }
            }
            
            Log.d(TAG, "✅ Recording thread finished, total bytes: $bytesRead")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error writing audio data: ${e.message}", e)
        } finally {
            try {
                outputStream?.close()
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error closing output stream: ${e.message}")
            }
        }
    }
    
    /**
     * Add WAV header to raw PCM file
     */
    private fun addWavHeader(file: File) {
        try {
            val audioLength = file.length()
            val totalDataLen = audioLength + 36
            val byteRate = sampleRate * 1 * 16 / 8  // 1 channel, 16-bit
            
            val raf = RandomAccessFile(file, "rw")
            raf.seek(0)
            
            // Write WAV header in little-endian format
            raf.write("RIFF".toByteArray())
            writeIntLE(raf, totalDataLen.toInt())
            raf.write("WAVE".toByteArray())
            raf.write("fmt ".toByteArray())
            writeIntLE(raf, 16) // Sub-chunk size
            writeShortLE(raf, 1) // Audio format (PCM)
            writeShortLE(raf, 1) // Number of channels (mono)
            writeIntLE(raf, sampleRate) // Sample rate
            writeIntLE(raf, byteRate) // Byte rate
            writeShortLE(raf, 2) // Block align
            writeShortLE(raf, 16) // Bits per sample
            raf.write("data".toByteArray())
            writeIntLE(raf, audioLength.toInt())
            
            raf.close()
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error adding WAV header: ${e.message}", e)
        }
    }
    
    /**
     * Write int in little-endian format
     */
    private fun writeIntLE(raf: RandomAccessFile, value: Int) {
        raf.writeByte(value and 0xFF)
        raf.writeByte((value shr 8) and 0xFF)
        raf.writeByte((value shr 16) and 0xFF)
        raf.writeByte((value shr 24) and 0xFF)
    }
    
    /**
     * Write short in little-endian format
     */
    private fun writeShortLE(raf: RandomAccessFile, value: Int) {
        raf.writeByte(value and 0xFF)
        raf.writeByte((value shr 8) and 0xFF)
    }
    
    /**
     * Check if currently recording
     */
    fun isRecording(): Boolean {
        return isRecording
    }
}

