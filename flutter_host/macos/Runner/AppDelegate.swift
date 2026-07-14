import Cocoa
import FlutterMacOS

@NSApplicationMain
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(
    _ sender: NSApplication
  ) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    guard let controller = mainFlutterWindow?.contentViewController
            as? FlutterViewController else { return }

    InputInjectorPlugin.register(
      with: controller.registrar(forPlugin: "InputInjectorPlugin")!
    )

    if #available(macOS 12.3, *) {
      ScreenCapturePlugin.register(
        with: controller.registrar(forPlugin: "ScreenCapturePlugin")!
      )
    }
  }
}
