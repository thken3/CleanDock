import AppKit

let arguments = CommandLine.arguments
if arguments.contains("--dump") {
    DebugTools.dump()
    exit(0)
}
if let index = arguments.firstIndex(of: "--shot"), index + 1 < arguments.count {
    DebugTools.shot(to: arguments[index + 1])
    exit(0)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
