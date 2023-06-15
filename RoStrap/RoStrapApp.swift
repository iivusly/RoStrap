//
//  RoStrapApp.swift
//  RoStrap
//
//  Created by iivusly on 5/10/23.
//

import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
	var openArguments: [String] = []
	
	func application(_ application: NSApplication, open urls: [URL]) {
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

@main
struct RoStrapApp: App {
	@NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

	@State var stateMessage = "Getting latest version..."
	@State var stateValue: Double?
	@State var throwingError: String?
	@State var isErroring = false
	
	@State var observations: [NSKeyValueObservation] = []
	
	func checkForUpdate() async throws {
		let updater = await RobloxUpdater()
		let currentVersion = UserDefaults.standard.string(forKey: "RobloxVersion")
		let channel = try await updater.getPlayerChannel()
		let version = try await updater.getVersionData(channel: channel)
		NSLog("\(currentVersion) ==? \(version.clientVersionUpload)")
		if (currentVersion != version.clientVersionUpload) {
			let downloadedURL = try await withCheckedThrowingContinuation({ continuation in
				let downloadTask = updater.getRobloxBinary(channel: channel, version: version) {result in
					continuation.resume(with: result)
				}
				
				stateMessage = "Downloading Roblox Version \(version.version)"
				observations.append(downloadTask.progress.observe(\.fractionCompleted, options: [.new], changeHandler: { progress, changed in
					stateValue = changed.newValue
				}))
			})
			
			let appPath = try updater.processRobloxBinary(path: downloadedURL, version: version)
			stateValue = nil
			UserDefaults.standard.setValue(version.clientVersionUpload, forKey: "RobloxVersion")
			UserDefaults.standard.setValue(appPath.path(percentEncoded: false), forKey: "RobloxAppPath")
		}
	}
	
    var body: some Scene {
		Window("Bootstrapper", id: "RobloxBootstrapper") {
			ContentView(stateMessage: $stateMessage, stateValue: $stateValue)
				.frame(alignment: .center)
				.task {
					let window: NSWindow = NSApplication.shared.windows.first!
					window.standardWindowButton(.zoomButton)?.isHidden = true
					window.isMovableByWindowBackground = true
					window.backgroundColor = .clear
					window.level = .floating
					window.center()
					
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
						let process = try Process.run(binaryPath, arguments: delegate.openArguments)
						
						
						NSApplication.shared.terminate(nil)
					}
					
					let result = await task.result
					switch result {
						case .success(()): break
					case .failure(let error):
						NSLog(error.localizedDescription)
						throwingError = error.localizedDescription
						isErroring = true
					}
				}
				.alert("Startup Error", isPresented: $isErroring, presenting: $throwingError) {_ in
					Button("Close") {
						NSApplication.shared.terminate(nil)
					}
				}
		}
		.windowStyle(.hiddenTitleBar)
		.windowResizability(.contentSize)
		.commandsRemoved()
    }
}
