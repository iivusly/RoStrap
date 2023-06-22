//
//  RobloxUpdater.swift
//  RoStrap
//
//  Created by iivusly on 5/10/23.
//

import Foundation
import AppKit

class RobloxUpdater {
	struct clientVersionResponse: Decodable {
		let version: String
		let clientVersionUpload: String
		let bootstrapperVersion: String
		let nextClientVersionUpload: String?
		let nextClientVersion: String?
	}

	struct userChannelResponse: Decodable {
		let channelName: String
	}
	
	// MARK: - Properties

	static let setupServers: [URL] = [
		URL(string: "https://setup.rbxcdn.com")!,
		URL(string: "https://setup-ak.rbxcdn.com")!,
		URL(string: "https://setup.roblox.com")!
	]
	
	static let clientSetupApi: URL = .init(string: "https://clientsettingscdn.roblox.com/")!
	
	// TODO: Figure out how to download from a channel
	static let channels: [String] = [
		"LIVE",
		"ZCanary",
		"zIntegration"
	]
	
	static let binaryType: String = "MacPlayer"
	
	var setupServer: URL!
	
	init() async {
		var server: URL?
		
		for url in RobloxUpdater.setupServers {
			do {
				let _ = try await self.stringWithContentsOfURL(url)
				NSLog("setupServer = \(url.absoluteString)")
				server = url
				break
			} catch {
				continue
			}
		}
		
		if server == nil {
			fatalError("Roblox servers are down?")
		} else {
			self.setupServer = server!
		}
	}
	
	let robloxUpdateURLSession = URLSession.shared
	
	// MARK: - Functions
	func stringWithContentsOfURL(_ url: URL, completionHandler: @escaping (Result<String, Error>) -> Void) -> URLSessionDataTask {
		let urlRequest = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10.0)
		
		let task = robloxUpdateURLSession.dataTask(with: urlRequest) { data, _, error in
			if (data != nil) {
				let stringContent = String(data: data!, encoding: .ascii)
				completionHandler(.success(stringContent ?? ""))
			} else {
				completionHandler(.failure(error!))
			}
		}
		
		task.resume()
		
		return task
	}
	
	func stringWithContentsOfURL(_ url: URL) async throws -> String {
		return try await withCheckedThrowingContinuation { (continuation) in
			let _ = stringWithContentsOfURL(url) { result in
				continuation.resume(with: result)
			}
		}
	}
	
	func fileWithContentsOfURL(url: URL, completionHandler: @escaping (Result<URL, Error>) -> Void) -> URLSessionDownloadTask {
		let urlRequest = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 10.0)
		
		let task = robloxUpdateURLSession.downloadTask(with: urlRequest) { fileURL, response, error in
			if (fileURL != nil) {
				if let data = try? Data(contentsOf: fileURL!) {
					URLCache.shared.storeCachedResponse(CachedURLResponse(response: response!, data: data), for: urlRequest)
				}
				
				let renameURL = fileURL!.deletingPathExtension().appendingPathExtension(url.pathExtension)
				_ = Task {
					try FileManager.default.moveItem(at: fileURL!, to: renameURL)
				}
				
				completionHandler(.success(renameURL))
			} else {
				completionHandler(.failure(error!))
			}
		}
		
		task.resume()
		
		return task
	}
	
	func fileWithContentsOfURL(url: URL) async throws -> URL {
		return try await withCheckedThrowingContinuation { (continuation) in
			let _ = fileWithContentsOfURL(url: url) { result in
				continuation.resume(with: result)
			}
		}
	}
	
	func getPlayerChannel() async throws -> userChannelResponse {
		let url = URL(
			string: "v2/user-channel?binaryType=\(RobloxUpdater.binaryType)",
			relativeTo: RobloxUpdater.clientSetupApi
		)!
		let data = try await self.stringWithContentsOfURL(url)
		
		return try JSONDecoder().decode(userChannelResponse.self, from: data.data(using: .ascii)!)
	}
	
	func getVersionData(channel: userChannelResponse = userChannelResponse(channelName: channels[1])) async throws -> clientVersionResponse {
		let url = URL(
			string: "v2/client-version/\(RobloxUpdater.binaryType)/channel/\(channel.channelName.lowercased())",
			relativeTo: RobloxUpdater.clientSetupApi
		)!
		
		let data = try await self.stringWithContentsOfURL(url)
		
		return try JSONDecoder().decode(clientVersionResponse.self, from: data.data(using: .ascii)!)
	}
	
	func getRobloxBinary(channel: userChannelResponse, version: clientVersionResponse, completionHandler: @escaping (Result<URL, Error>) -> Void) -> URLSessionDownloadTask {
		// FileManager.default.temporaryDirectory
		
		let url = URL(
			string: "mac/\(version.clientVersionUpload)-RobloxPlayer.zip",
			relativeTo: self.setupServer
		)!
		
		return fileWithContentsOfURL(url: url) { result in
			completionHandler(result)
		}
	}
	
	private func unzipDirectory(path: URL, destination: URL) throws -> Int32 {
		// TODO: Find a more efficient method of unzipping
        let process = Process()
        process.arguments = ["-qo", path.path, "-d", destination.path(percentEncoded: false)]
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        try process.run()
		process.waitUntilExit()
		return process.terminationStatus
	}
	
	func processRobloxBinary(path: URL, version: clientVersionResponse) throws -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent(Bundle.main.bundleIdentifier!, conformingTo: .directory)
		try FileManager.default.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
		
		let _ = try unzipDirectory(path: path, destination: applicationSupport)
		
        let oldName = applicationSupport.appendingPathComponent("RobloxPlayer.app", conformingTo: .directory)
        let newName = applicationSupport.appendingPathComponent("\(version.clientVersionUpload).app", conformingTo: .directory)
		
		try FileManager.default.moveItem(at: oldName, to: newName)
		
		let app = Bundle(url: newName)!
		
        try FileManager.default.removeItem(at: (app.executableURL?.deletingLastPathComponent().appendingPathComponent("Roblox.app", conformingTo: .directory))!)
		
		NSWorkspace.shared.setIcon(Bundle.main.image(forResource: "AppIcon"), forFile: app.bundlePath, options: .excludeQuickDrawElementsIconCreationOption)
		
		return app.bundleURL
	}
}
