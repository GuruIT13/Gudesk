import Cocoa
import ScreenCaptureKit
import CoreGraphics
import FlutterMacOS

@available(macOS 12.3, *)
class ScreenCapturePlugin: NSObject, FlutterPlugin, SCStreamOutput, SCStreamDelegate {
  private var stream: SCStream?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "gudesk/screen_capture",
      binaryMessenger: registrar.messenger
    )
    let instance = ScreenCapturePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "hasPermission":
      result(CGPreflightScreenCaptureAccess())
    case "requestPermission":
      result(CGRequestScreenCaptureAccess())
    case "startCapture":
      startCapture(result: result)
    case "stopCapture":
      stopCapture(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startCapture(result: @escaping FlutterResult) {
    SCShareableContent.getWithCompletionHandler { [weak self] content, error in
      DispatchQueue.main.async { [weak self] in
        guard let self = self, let content = content, error == nil else {
          result(FlutterError(
            code: "CAPTURE_FAILED",
            message: error?.localizedDescription ?? "Failed to get shareable content",
            details: nil
          ))
          return
        }

        guard let display = content.displays.first else {
          result(FlutterError(code: "NO_DISPLAY", message: "No display found", details: nil))
          return
        }

        let config = SCStreamConfiguration()
        config.width = 1920
        config.height = 1080
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let newStream = SCStream(filter: filter, configuration: config, delegate: self)

        do {
          try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
          self.stream = newStream
          newStream.startCapture { [weak self] error in
            DispatchQueue.main.async {
              if let error = error {
                self?.stream = nil
                result(FlutterError(
                  code: "START_FAILED",
                  message: error.localizedDescription,
                  details: nil
                ))
              } else {
                result(nil)
              }
            }
          }
        } catch {
          result(FlutterError(
            code: "STREAM_ERROR",
            message: error.localizedDescription,
            details: nil
          ))
        }
      }
    }
  }

  private func stopCapture(result: @escaping FlutterResult) {
    guard let stream = stream else {
      result(nil)
      return
    }
    stream.stopCapture { _ in }
    self.stream = nil
    result(nil)
  }

  // SCStreamOutput — receives captured frames
  func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard type == .screen else { return }
    // Frames are captured here. WebRTC video track integration (pushing RTCVideoFrame
    // into an RTCVideoSource) requires access to flutter_webrtc's internal source
    // registry, which is wired up as part of the full native WebRTC integration.
    // For Phase F.5b the capture pipeline is established; frame forwarding to WebRTC
    // is completed when the RTCVideoSource is exposed via flutter_webrtc's API.
    _ = sampleBuffer
  }

  // SCStreamDelegate
  func stream(_ stream: SCStream, didStopWithError error: Error) {
    self.stream = nil
  }
}
