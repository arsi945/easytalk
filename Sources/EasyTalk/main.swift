import AppKit
import EasyTalkLearning

// Explicit one-use provisioning: stdin only, no arguments/files/logs containing secrets.
if CommandLine.arguments.contains("--provision-connection") {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard data.count <= 16384, let config = try? JSONDecoder().decode(ConnectionSettings.self, from: data), config.url != nil,
          MacKeychainVault().write(config) else { fputs("Connection could not be saved in Keychain.\n", stderr); exit(1) }
    print("Connection saved in macOS Keychain."); exit(0)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(CommandLine.arguments.contains("--desktop-check") ? .prohibited : .regular)
app.run()
