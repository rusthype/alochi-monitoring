import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    // Safe floor for 1280x720 monitors with the Windows taskbar taking ~48px
    // (leaving ~672px usable height) — see
    // alochi/docs/PROMPT_FLUTTER_ADAPTIVE_RESPONSIVE_REFLOW_AND_SAFE_MINSIZE.md.
    self.minSize = NSSize(width: 800, height: 540)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
