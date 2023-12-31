//
//  RoStrapApp.swift
//  RoStrap
//
//  Created by iivusly on 5/10/23.
//

import SwiftUI
import Sparkle
import Sentry

// TODO: Move away from AppDelegate
final class AppDelegate: NSObject, NSApplicationDelegate {
    var openArguments: [String] = []

    func application(_: NSApplication, open urls: [URL]) {
        guard let url = urls.first else {
            return
        }

        Task {
            let parser = RobloxURLHandler(url.absoluteString)
            try parser.parse()
            openArguments = parser.formatForRobloxPlayer()
        }
    }
}

enum WindowError: Error {
    case cannotCreateWindow
}

@main
struct RoStrapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @State var stateMessage = "Getting latest version..."
    @State var stateValue: Double?
    @State var throwingError: String?
    @State var isErroring = false

    @State var observations: [NSKeyValueObservation] = []
    
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    
    init() {
        #if !DEBUG
        SentrySDK.start { options in
            options.dsn = "https://1e675d6cfc2143e6a8a7d631d3796a15@o4505523991085056.ingest.sentry.io/4505523997048832"
            options.debug = true // Enabled debug when first installing is always helpful

            // Set tracesSampleRate to 1.0 to capture 100% of transactions for performance monitoring.
            // We recommend adjusting this value in production.
            options.tracesSampleRate = 1.0
        }
        #endif
    }

    func checkForUpdate() async throws {
        updaterController.updater.automaticallyChecksForUpdates = true
        updaterController.updater.automaticallyDownloadsUpdates = true
        updaterController.checkForUpdates(self) // Check for updates
        
        let updater = RobloxUpdater()
        
        // Check for the overridden version
        let overrideVersion = UserDefaults.standard.string(forKey: "RobloxOverrideVersion")
        if (overrideVersion != nil) {
            // Check if the version is already downloaded
            let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent(Bundle.main.bundleIdentifier!, conformingTo: .directory)
            let appPath = applicationSupport.appending(path: overrideVersion!)
            if (FileManager.default.fileExists(atPath: appPath.path)) {
                // Set values and exit
                UserDefaults.standard.setValue(overrideVersion!, forKey: "RobloxVersion")
                UserDefaults.standard.setValue(appPath.path(percentEncoded: false), forKey: "RobloxAppPath")
            } else {
                // Download Roblox Version
                let downloadedURL = try await withCheckedThrowingContinuation { continuation in
                    let downloadTask = updater.getRobloxBinary(channel: "live", version: overrideVersion!) { result in
                        continuation.resume(with: result)
                    }

                    stateMessage = "Downloading Roblox Version \(overrideVersion!)"
                    observations.append(downloadTask.progress.observe(\.fractionCompleted, options: [.new], changeHandler: { _, changed in
                        // TODO: Fix mutations from sendable closures for Swift 6
                        stateValue = changed.newValue
                    }))
                }

                let appPath = try updater.processRobloxBinary(path: downloadedURL, version: overrideVersion!)
                stateValue = nil
                UserDefaults.standard.setValue(overrideVersion!, forKey: "RobloxVersion")
                UserDefaults.standard.setValue(appPath.path(percentEncoded: false), forKey: "RobloxAppPath")
            }
        } else {
            let currentVersion = UserDefaults.standard.string(forKey: "RobloxVersion")
            let channel = try await updater.getDefaultChannel()
            let version = try await updater.getVersionData(channel: channel.channelName)
            NSLog("\(String(describing: currentVersion)) ==? \(version.clientVersionUpload)")
            if currentVersion != version.clientVersionUpload {
                let downloadedURL = try await withCheckedThrowingContinuation { continuation in
                    let downloadTask = updater.getRobloxBinary(channel: channel.channelName, version: version.clientVersionUpload) { result in
                        continuation.resume(with: result)
                    }

                    stateMessage = "Downloading Roblox Version \(version.version)"
                    observations.append(downloadTask.progress.observe(\.fractionCompleted, options: [.new], changeHandler: { _, changed in
                        // TODO: Fix mutations from sendable closures for Swift 6
                        stateValue = changed.newValue
                    }))
                }

                let appPath = try updater.processRobloxBinary(path: downloadedURL, version: version.clientVersionUpload)
                stateValue = nil
                UserDefaults.standard.setValue(version.clientVersionUpload, forKey: "RobloxVersion")
                UserDefaults.standard.setValue(appPath.path(percentEncoded: false), forKey: "RobloxAppPath")
            }
        }
    }

    var body: some Scene {
        Window("Bootstrapper", id: "RobloxBootstrapper") {
            MainView(stateMessage: $stateMessage, stateValue: $stateValue)
                .frame(alignment: .center)
                .task {
                    // Select the first window, else error
                    guard let window: NSWindow = NSApplication.shared.windows.first(where: { window in
                        window.title == "Bootstrapper"
                    }) else {
                        NSAlert(error: WindowError.cannotCreateWindow).runModal()
                        return NSApplication.shared.terminate(nil)
                    }
                    
                    // Configure the window
                    window.isMovableByWindowBackground = true
                    window.level = .floating
                    window.center()
                    window.makeKey()
                    
                    // Style the window
                    window.standardWindowButton(.zoomButton)?.isHidden = true
                    window.backgroundColor = .clear
                    window.isOpaque = false

                    NSApplication.shared.activate(ignoringOtherApps: true)

                    let task = Task {
                        #if DEBUG
                            LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
                            // try await Task.sleep(nanoseconds: UInt64(20 * Double(NSEC_PER_SEC))) // Delay so we can test
                        #endif
                        try await checkForUpdate()
                        let appPath = UserDefaults.standard.url(forKey: "RobloxAppPath")!
                        let binaryPath = appPath.appending(components: "Contents/MacOS/RobloxPlayer")

                        stateMessage = "Starting Roblox..."

                        print(delegate.openArguments.joined(separator: " "))
                        let process = Process()
                        // let output = Pipe()

                        process.executableURL = binaryPath
                        process.arguments = delegate.openArguments
                        // TODO: Roblox does not like it when we pipe the output, so test for crashes
                        // process.standardError = output
                        // process.standardOutput = output

                        try process.run()

                        if process.isRunning {
                            // TODO: we should wait until the roblox window is shown
                            // The old way of doing this is waiting for a semaphore called "/robloxPlayerStartedEvent",
                            // But it seems to not be triggered now...
                        }

                        NSApplication.shared.terminate(self)
                    }

                    let result = await task.result
                    switch result {
                    case .success(()): break
                    case let .failure(error):
                        NSAlert(error: error).runModal()
                        NSApplication.shared.terminate(self)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commandsRemoved()

        MenuBarExtra("RoStrap Menu", systemImage: "gamecontroller") {
            PopUpView()
        }.menuBarExtraStyle(.window)
    }
}
