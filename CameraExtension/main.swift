import CoreMediaIO
import Foundation

let info = Bundle.main.infoDictionary
extensionLog.notice("starting \(info?["CFBundleShortVersionString"] as? String ?? "?", privacy: .public) (\(info?["CFBundleVersion"] as? String ?? "?", privacy: .public)), process \(getpid(), privacy: .public)")

let providerSource = ProviderSource(clientQueue: nil)
CMIOExtensionProvider.startService(provider: providerSource.provider)
extensionLog.notice("service started; waiting for clients")

CFRunLoopRun()
