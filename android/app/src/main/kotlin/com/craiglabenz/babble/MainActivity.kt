package com.craiglabenz.babble

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "NativeAudioCapture"
        private const val CONTROL_CHANNEL = "flutter_edge_ai_speech/audio_control"
        private const val STREAM_CHANNEL = "flutter_edge_ai_speech/audio_stream"
        private const val PERMISSION_REQUEST_CODE = 4201
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val audioControlExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "NativeAudioControlExecutor").apply { isDaemon = true }
    }
    private val isRecording = AtomicBoolean(false)
    private var eventSink: EventChannel.EventSink? = null
    private var audioRecord: AudioRecord? = null
    private var recordingThread: Thread? = null
    private var pendingStartResult: MethodChannel.Result? = null
    private var pendingSampleRate: Int = 16000

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CONTROL_CHANNEL
        ).setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            STREAM_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                Log.i(TAG, "EventChannel onListen attached")
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                Log.i(TAG, "EventChannel onCancel detached")
                eventSink = null
            }
        })
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val sampleRate = call.argument<Int>("sampleRate") ?: 16000
                Log.i(TAG, "'start' invoked (sampleRate=$sampleRate)")
                if (ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED
                ) {
                    startAudioRecord(sampleRate, result)
                } else {
                    pendingSampleRate = sampleRate
                    pendingStartResult = result
                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.RECORD_AUDIO),
                        PERMISSION_REQUEST_CODE
                    )
                }
            }
            "stop" -> {
                Log.i(TAG, "'stop' invoked")
                audioControlExecutor.execute {
                    stopAudioRecord()
                    mainHandler.post { result.success(null) }
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val result = pendingStartResult
            pendingStartResult = null
            if (result != null) {
                if (grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
                ) {
                    Log.i(TAG, "Microphone permission GRANTED")
                    startAudioRecord(pendingSampleRate, result)
                } else {
                    Log.w(TAG, "Microphone permission DENIED")
                    result.error(
                        "PERMISSION_DENIED",
                        "Microphone permission was denied.",
                        null
                    )
                }
            }
        }
    }

    private fun startAudioRecord(sampleRate: Int, result: MethodChannel.Result) {
        audioControlExecutor.execute {
            stopAudioRecord()
            try {
                val minBuffer = AudioRecord.getMinBufferSize(
                    sampleRate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT
                )
                val bufferSize = maxOf(minBuffer, sampleRate / 10 * 2)
                val recorder = AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    sampleRate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    bufferSize
                )

                if (recorder.state != AudioRecord.STATE_INITIALIZED) {
                    recorder.release()
                    mainHandler.post {
                        result.error(
                            "AUDIO_RECORD_INIT_FAILED",
                            "AudioRecord failed to initialize at ${sampleRate}Hz.",
                            null
                        )
                    }
                    return@execute
                }

                audioRecord = recorder
                isRecording.set(true)
                recorder.startRecording()

                recordingThread = Thread {
                    val frameSamples = 1024
                    val shortBuffer = ShortArray(frameSamples)
                    var frameCount = 0
                    while (isRecording.get()) {
                        val read = recorder.read(shortBuffer, 0, frameSamples)
                        if (read > 0) {
                            val byteBuffer = ByteBuffer
                                .allocate(read * 2)
                                .order(ByteOrder.LITTLE_ENDIAN)
                            for (i in 0 until read) {
                                byteBuffer.putShort(shortBuffer[i])
                            }
                            val bytes = byteBuffer.array()
                            frameCount++
                            if (frameCount == 1 || frameCount % 50 == 0) {
                                Log.d(TAG, "Streaming 16kHz PCM frame #$frameCount ($read samples)")
                            }
                            mainHandler.post {
                                eventSink?.success(bytes)
                            }
                        }
                    }
                }.apply {
                    name = "NativeAudioCaptureThread"
                    start()
                }

                Log.i(TAG, "AudioRecord started successfully at ${sampleRate}Hz")
                mainHandler.post { result.success(null) }
            } catch (e: SecurityException) {
                mainHandler.post { result.error("PERMISSION_DENIED", e.message, null) }
            } catch (e: Exception) {
                mainHandler.post { result.error("AUDIO_CAPTURE_ERROR", e.message, null) }
            }
        }
    }

    private fun stopAudioRecord() {
        isRecording.set(false)
        try {
            recordingThread?.join(300)
        } catch (_: InterruptedException) {
        }
        recordingThread = null

        audioRecord?.let { recorder ->
            try {
                if (recorder.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                    recorder.stop()
                }
            } catch (_: Exception) {
            }
            recorder.release()
        }
        audioRecord = null
    }

    override fun onDestroy() {
        stopAudioRecord()
        super.onDestroy()
    }
}
