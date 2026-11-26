import AppKit
import Darwin

private var noCoreFiles = rlimit(rlim_cur: 0, rlim_max: 0)
if setrlimit(RLIMIT_CORE, &noCoreFiles) != 0 {
    fputs("PwdHash could not disable core files.\n", stderr)
    exit(EXIT_FAILURE)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
withExtendedLifetime(delegate) {}
