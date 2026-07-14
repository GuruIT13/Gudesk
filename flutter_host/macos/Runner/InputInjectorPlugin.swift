import Cocoa
import FlutterMacOS
import ApplicationServices

class InputInjectorPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "gudesk/input_injector",
      binaryMessenger: registrar.messenger
    )
    let instance = InputInjectorPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]

    switch call.method {
    case "hasPermission":
      result(AXIsProcessTrusted())

    case "requestPermission":
      let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
      let trusted = AXIsProcessTrustedWithOptions(options)
      result(trusted)

    case "injectMouseMove":
      guard let x = args?["x"] as? Double, let y = args?["y"] as? Double else {
        result(FlutterError(code: "INVALID_ARGS", message: "x and y required", details: nil))
        return
      }
      let point = CGPoint(x: x, y: y)
      let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                          mouseCursorPosition: point, mouseButton: .left)
      event?.post(tap: .cghidEventTap)
      result(nil)

    case "injectMouseClick":
      guard let button = args?["button"] as? String,
            let x = args?["x"] as? Double,
            let y = args?["y"] as? Double else {
        result(FlutterError(code: "INVALID_ARGS", message: "button, x, y required", details: nil))
        return
      }
      let point = CGPoint(x: x, y: y)
      let (downType, upType, btn): (CGEventType, CGEventType, CGMouseButton) = button == "right"
        ? (.rightMouseDown, .rightMouseUp, .right)
        : (.leftMouseDown, .leftMouseUp, .left)
      CGEvent(mouseEventSource: nil, mouseType: downType,
              mouseCursorPosition: point, mouseButton: btn)?.post(tap: .cghidEventTap)
      CGEvent(mouseEventSource: nil, mouseType: upType,
              mouseCursorPosition: point, mouseButton: btn)?.post(tap: .cghidEventTap)
      result(nil)

    case "injectMouseScroll":
      guard let dy = args?["dy"] as? Double else {
        result(FlutterError(code: "INVALID_ARGS", message: "dy required", details: nil))
        return
      }
      let dx = args?["dx"] as? Double ?? 0.0
      let scroll1 = Int32(dy * -3)
      let scroll2 = Int32(dx * -3)
      let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                          wheelCount: 2, wheel1: scroll1, wheel2: scroll2, wheel3: 0)
      event?.post(tap: .cghidEventTap)
      result(nil)

    case "injectKey":
      guard let keyCode = args?["keyCode"] as? Int,
            let down = args?["down"] as? Bool else {
        result(FlutterError(code: "INVALID_ARGS", message: "keyCode and down required", details: nil))
        return
      }
      guard keyCode >= 0 && keyCode <= Int(UInt16.max) else {
        result(FlutterError(code: "INVALID_ARGS", message: "keyCode out of range", details: nil))
        return
      }
      let modifiers = args?["modifiers"] as? [String] ?? []
      var flags: CGEventFlags = []
      if modifiers.contains("shift") { flags.insert(.maskShift) }
      if modifiers.contains("ctrl") { flags.insert(.maskControl) }
      if modifiers.contains("alt") { flags.insert(.maskAlternate) }
      if modifiers.contains("meta") || modifiers.contains("cmd") { flags.insert(.maskCommand) }
      let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: down)
      event?.flags = flags
      event?.post(tap: .cghidEventTap)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
