import AppKit

let arguments = CommandLine.arguments
if arguments.contains("--dump") {
    DebugTools.dump()
    exit(0)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
