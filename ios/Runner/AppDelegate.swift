import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var audioCaptureController: NativeAudioCaptureController?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if audioCaptureController == nil,
       let controller = window?.rootViewController as? FlutterViewController {
      audioCaptureController = NativeAudioCaptureController(
        messenger: controller.binaryMessenger
      )
      NSLog("[NativeAudioCapture] Registered channels via rootViewController fallback.")
    }
    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "NativeAudioCapturePlugin"
    ) {
      audioCaptureController = NativeAudioCaptureController(
        messenger: registrar.messenger()
      )
      NSLog("[NativeAudioCapture] Registered flutter_edge_ai_speech audio channels via engineBridge.")
    }
  }
}

final class NativeAudioCaptureController: NSObject, FlutterStreamHandler {
  private let controlChannel: FlutterMethodChannel
  private let streamChannel: FlutterEventChannel
  private let audioQueue = DispatchQueue(
    label: "com.translation_app.native_audio_queue",
    qos: .userInitiated
  )
  private var eventSink: FlutterEventSink?
  private var audioEngine: AVAudioEngine?
  private var isRunning = false
  private var frameCounter: Int = 0

  init(messenger: FlutterBinaryMessenger) {
    controlChannel = FlutterMethodChannel(
      name: "flutter_edge_ai_speech/audio_control",
      binaryMessenger: messenger
    )
    streamChannel = FlutterEventChannel(
      name: "flutter_edge_ai_speech/audio_stream",
      binaryMessenger: messenger
    )
    super.init()

    controlChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleMethodCall(call, result: result)
    }
    streamChannel.setStreamHandler(self)
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    NSLog("[NativeAudioCapture] EventChannel onListen attached.")
    self.eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    NSLog("[NativeAudioCapture] EventChannel onCancel detached.")
    self.eventSink = nil
    return nil
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      let args = call.arguments as? [String: Any]
      let sampleRate = (args?["sampleRate"] as? Int) ?? 16000
      NSLog("[NativeAudioCapture] 'start' invoked (targetSampleRate=\(sampleRate)).")
      requestPermissionAndStart(targetSampleRate: Double(sampleRate), result: result)
    case "stop":
      NSLog("[NativeAudioCapture] 'stop' invoked.")
      audioQueue.async { [weak self] in
        self?.stopEngine()
        DispatchQueue.main.async {
          result(nil)
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func requestPermissionAndStart(
    targetSampleRate: Double,
    result: @escaping FlutterResult
  ) {
    AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
      guard let self = self else { return }
      if !granted {
        NSLog("[NativeAudioCapture] Microphone permission DENIED.")
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "PERMISSION_DENIED",
              message: "Microphone permission was denied. Please enable Microphone access in Settings.",
              details: nil
            )
          )
        }
        return
      }
      NSLog("[NativeAudioCapture] Microphone permission GRANTED. Starting AVAudioEngine on background queue...")
      self.audioQueue.async { [weak self] in
        self?.startEngine(targetSampleRate: targetSampleRate) { flutterOutcome in
          DispatchQueue.main.async {
            result(flutterOutcome)
          }
        }
      }
    }
  }

  private func configureAndActivateAudioSession(
    _ session: AVAudioSession,
    targetSampleRate: Double
  ) throws {
    let configurations: [(
      category: AVAudioSession.Category,
      mode: AVAudioSession.Mode,
      options: AVAudioSession.CategoryOptions,
      setPreferredRate: Bool,
      label: String
    )] = [
      (
        .playAndRecord,
        .voiceChat,
        [.defaultToSpeaker, .allowBluetooth],
        true,
        "playAndRecord/voiceChat/defaultToSpeaker+bluetooth"
      ),
      (
        .playAndRecord,
        .voiceChat,
        [.defaultToSpeaker],
        false,
        "playAndRecord/voiceChat/defaultToSpeaker"
      ),
      (
        .playAndRecord,
        .default,
        [.defaultToSpeaker, .allowBluetooth],
        true,
        "playAndRecord/default/defaultToSpeaker+bluetooth"
      ),
      (
        .playAndRecord,
        .default,
        [.defaultToSpeaker],
        false,
        "playAndRecord/default/defaultToSpeaker"
      ),
      (
        .playAndRecord,
        .default,
        [.defaultToSpeaker, .allowBluetooth, .mixWithOthers],
        false,
        "playAndRecord/default/defaultToSpeaker+bluetooth+mix"
      ),
      (
        .playAndRecord,
        .default,
        [.defaultToSpeaker, .mixWithOthers],
        false,
        "playAndRecord/default/defaultToSpeaker+mix"
      ),
      (
        .record,
        .default,
        [.allowBluetooth],
        false,
        "record/default/bluetooth"
      ),
      (
        .record,
        .measurement,
        [],
        false,
        "record/measurement/none"
      ),
      (
        .record,
        .default,
        [.mixWithOthers],
        false,
        "record/default/mix"
      ),
      (
        .record,
        .default,
        [],
        false,
        "record/default/none"
      ),
    ]

    var lastError: Error?
    for attempt in 1...2 {
      for config in configurations {
        do {
          try session.setCategory(
            config.category,
            mode: config.mode,
            options: config.options
          )
          if config.setPreferredRate {
            try? session.setPreferredSampleRate(targetSampleRate)
          }
          try? session.setPreferredIOBufferDuration(0.02)
          try session.setActive(true)
          NSLog(
            "[NativeAudioCapture] Activated AVAudioSession with \(config.label) (attempt \(attempt))."
          )
          return
        } catch {
          lastError = error
          NSLog(
            "[NativeAudioCapture] AVAudioSession config '\(config.label)' (attempt \(attempt)) failed (\(error.localizedDescription)); trying fallback..."
          )
          try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
      }
      if attempt == 1 {
        Thread.sleep(forTimeInterval: 0.15)
      }
    }

    if let error = lastError {
      throw error
    }
  }

  private func startEngine(
    targetSampleRate: Double,
    result: @escaping FlutterResult
  ) {
    if isRunning {
      stopEngine()
    }

    do {
      let session = AVAudioSession.sharedInstance()
      try configureAndActivateAudioSession(
        session,
        targetSampleRate: targetSampleRate
      )

      let engine = AVAudioEngine()
      let inputNode = engine.inputNode
      var hardwareFormat = inputNode.outputFormat(forBus: 0)
      if hardwareFormat.sampleRate <= 0 || hardwareFormat.channelCount <= 0 {
        hardwareFormat = inputNode.inputFormat(forBus: 0)
      }

      NSLog(
        "[NativeAudioCapture] Hardware input format: sampleRate=\(hardwareFormat.sampleRate), channels=\(hardwareFormat.channelCount)"
      )

      guard hardwareFormat.sampleRate > 0 && hardwareFormat.channelCount > 0 else {
        result(
          FlutterError(
            code: "AUDIO_FORMAT_INVALID",
            message: "Invalid hardware audio input format (sampleRate=\(hardwareFormat.sampleRate)).",
            details: nil
          )
        )
        return
      }

      guard let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: targetSampleRate,
        channels: 1,
        interleaved: false
      ) else {
        result(
          FlutterError(
            code: "AUDIO_FORMAT_ERROR",
            message: "Unable to create 16kHz mono Float32 target format.",
            details: nil
          )
        )
        return
      }

      guard let converter = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
        result(
          FlutterError(
            code: "AUDIO_CONVERTER_ERROR",
            message: "Unable to create AVAudioConverter from hardware format to 16kHz mono.",
            details: nil
          )
        )
        return
      }

      frameCounter = 0

      inputNode.installTap(onBus: 0, bufferSize: 1024, format: hardwareFormat) {
        [weak self] (buffer, _) in
        guard let self = self else { return }

        let ratio = targetSampleRate / hardwareFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let outputBuffer = AVAudioPCMBuffer(
          pcmFormat: targetFormat,
          frameCapacity: outputFrameCapacity
        ) else {
          return
        }

        var error: NSError?
        var didProvideInput = false
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
          if didProvideInput {
            outStatus.pointee = .noDataNow
            return nil
          }
          didProvideInput = true
          outStatus.pointee = .haveData
          return buffer
        }

        guard status != .error, error == nil else {
          return
        }

        let frameLength = Int(outputBuffer.frameLength)
        guard frameLength > 0,
              let channelData = outputBuffer.floatChannelData?[0] else {
          return
        }

        let byteCount = frameLength * MemoryLayout<Float32>.size
        let data = Data(bytes: channelData, count: byteCount)
        let typedData = FlutterStandardTypedData(float32: data)

        self.frameCounter += 1
        let currentCount = self.frameCounter
        if currentCount == 1 || currentCount % 50 == 0 {
          NSLog(
            "[NativeAudioCapture] Captured 16kHz mono frame #\(currentCount): \(frameLength) samples"
          )
        }

        DispatchQueue.main.async { [weak self] in
          self?.eventSink?(typedData)
        }
      }

      engine.prepare()
      try engine.start()
      self.audioEngine = engine
      self.isRunning = true
      NSLog("[NativeAudioCapture] AVAudioEngine started successfully.")
      result(nil)
    } catch {
      NSLog("[NativeAudioCapture] Failed to start AVAudioEngine: \(error.localizedDescription)")
      result(
        FlutterError(
          code: "AUDIO_ENGINE_FAILURE",
          message: "Failed to start microphone capture: \(error.localizedDescription)",
          details: nil
        )
      )
    }
  }

  private func stopEngine() {
    if let engine = audioEngine {
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
      engine.reset()
      audioEngine = nil
    }
    isRunning = false
    do {
      try AVAudioSession.sharedInstance().setActive(
        false,
        options: .notifyOthersOnDeactivation
      )
    } catch {
      NSLog("[NativeAudioCapture] Note: deactivating AVAudioSession returned: \(error.localizedDescription)")
    }
    NSLog("[NativeAudioCapture] AVAudioEngine stopped (totalFrames=\(frameCounter)).")
  }
}
