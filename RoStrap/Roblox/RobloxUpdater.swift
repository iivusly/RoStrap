//
//  RobloxUpdater.swift
//  RoStrap
//
//  Created by iivusly on 5/10/23.
//

import AppKit
import Foundation
import ZIPFoundation

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

    enum updateErrors: Error {
        case cannotConnect, unzipFail
    }

    // MARK: - Properties

    static let setupServers: [URL] = [
        URL(string: "https://setup.rbxcdn.com")!,
        URL(string: "https://setup-ak.rbxcdn.com")!,
        URL(string: "https://setup.roblox.com")!,
    ]

    static let clientSetupApi: URL = .init(string: "https://clientsettingscdn.roblox.com/")!

    // TODO: Figure out how to download from a channel
    /* static let channels: [String] = [
        "LIVE",
        "ZCanary",
        "zIntegration",
    ] */

    static let binaryType: String = "MacPlayer"

    var setupServer: URL {
        for url in RobloxUpdater.setupServers {
            do {
                let semaphore = DispatchSemaphore(value: 0)
                var requestResult = Result {""}
                _ = stringWithContentsOfURL(url) { result in
                    requestResult = result
                    semaphore.signal()
                }
                semaphore.wait()
                
                _ = try requestResult.get()
                
                NSLog("setupServer = \(url.absoluteString)")
                return url
            } catch {
                continue
            }
        }
        
        fatalError("Roblox servers are down?")
    }

    let urlSession = URLSession.shared
    let fileManager = FileManager.default
    
    // TODO: Find out a better place to put Roblox binaries
    var robloxBinaryDirectory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent(Bundle.main.bundleIdentifier!, conformingTo: .directory)
    }

    // MARK: - Functions

    func stringWithContentsOfURL(_ url: URL, completionHandler: @escaping (Result<String, Error>) -> Void) -> URLSessionDataTask {
        let urlRequest = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10.0)

        let task = urlSession.dataTask(with: urlRequest) { data, _, error in
            if data != nil {
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
        return try await withCheckedThrowingContinuation { continuation in
            let _ = stringWithContentsOfURL(url) { result in
                continuation.resume(with: result)
            }
        }
    }

    func fileWithContentsOfURL(url: URL, completionHandler: @escaping (Result<URL, Error>) -> Void) -> URLSessionDownloadTask {
        let urlRequest = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 10.0)

        let task = urlSession.downloadTask(with: urlRequest) { fileURL, response, error in
            if fileURL != nil {
                if let data = try? Data(contentsOf: fileURL!) {
                    URLCache.shared.storeCachedResponse(CachedURLResponse(response: response!, data: data), for: urlRequest)
                }

                let renameURL = fileURL!.deletingPathExtension().appendingPathExtension(url.pathExtension)
                _ = Task {
                    try self.fileManager.moveItem(at: fileURL!, to: renameURL)
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
        return try await withCheckedThrowingContinuation { continuation in
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
        let data = try await stringWithContentsOfURL(url)

        return try JSONDecoder().decode(userChannelResponse.self, from: data.data(using: .ascii)!)
    }

    func getVersionData(channel: userChannelResponse = userChannelResponse(channelName: "live")) async throws -> clientVersionResponse {
        let url = URL(
            string: "v2/client-version/\(RobloxUpdater.binaryType)/channel/\(channel.channelName.lowercased())",
            relativeTo: RobloxUpdater.clientSetupApi
        )!

        let data = try await stringWithContentsOfURL(url)

        return try JSONDecoder().decode(clientVersionResponse.self, from: data.data(using: .ascii)!)
    }

    func getRobloxBinary(channel: Any?, version: String, completionHandler: @escaping (Result<URL, Error>) -> Void) -> URLSessionDownloadTask {
        let url = URL(
            string: "mac/\(version)-RobloxPlayer.zip",
            relativeTo: setupServer
        )!

        return fileWithContentsOfURL(url: url) { result in
            completionHandler(result)
        }
    }

    func processRobloxBinary(path: URL, version: String) throws -> URL {
        try fileManager.createDirectory(at: robloxBinaryDirectory, withIntermediateDirectories: true)
        
        let targetFile = robloxBinaryDirectory.appendingPathComponent("\(version).app", conformingTo: .directory)
        
        if ((try? targetFile.checkResourceIsReachable()) ?? false) {
            return targetFile
        }
        
        let temporaryDirectory = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: targetFile, create: true)

        try fileManager.unzipItem(at: path, to: temporaryDirectory)

        try fileManager.moveItem(at: temporaryDirectory.appending(path: "RobloxPlayer.app"), to: targetFile)

        let app = Bundle(url: targetFile)!

        try fileManager.removeItem(at: (app.executableURL?.deletingLastPathComponent().appendingPathComponent("Roblox.app", conformingTo: .directory))!)

        NSWorkspace.shared.setIcon(Bundle.main.image(forResource: "AppIcon"), forFile: app.bundlePath, options: .excludeQuickDrawElementsIconCreationOption)

        return app.bundleURL
    }
}
