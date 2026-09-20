#!/usr/bin/env xcrun swift

// Ask the input source registry whether a bundle identifier is actually there, and enabled.
//
// --register-input-source returning 0 does not mean it worked. After a bundle is replaced, the first call
// can succeed against the previous one's LaunchServices entry and report nothing wrong while the new
// bundle is registered nowhere - which looks exactly like a working install until the user opens the
// input menu and finds it missing.
//
// Usage: check_input_source.swift <bundle identifier>

import Carbon
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: check_input_source.swift <bundle identifier>\n".data(using: .utf8)!)
    exit(2)
}
let identifier = CommandLine.arguments[1]

let filter = [kTISPropertyBundleID as String: identifier] as CFDictionary
guard let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
      !sources.isEmpty else {
    FileHandle.standardError.write("""
        \(identifier) is not in the input source registry. --register-input-source may still have exited 0 \
        against a stale entry for the bundle it replaced. An ad-hoc signed bundle is the usual cause.\n
        """.data(using: .utf8)!)
    exit(1)
}

var disabled: [String] = []
for source in sources {
    guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
    let id = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    var enabled = false
    if let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) {
        enabled = CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
    }
    print("\(id): \(enabled ? "enabled" : "disabled")")
    if !enabled { disabled.append(id) }
}
if !disabled.isEmpty {
    FileHandle.standardError.write("registered but not enabled: \(disabled.joined(separator: ", "))\n".data(using: .utf8)!)
    exit(1)
}
