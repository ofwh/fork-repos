//
//  AlphaMetaDownloader.swift
//  ClashX Meta
//
//  Copyright © 2023 west2online. All rights reserved.
//

import Cocoa
import CryptoKit
import AsyncHTTPClient
import SwiftyJSON

class AlphaMetaDownloader: NSObject {

	enum errors: Error {
		case decodeReleaseInfoFailed
		case notFoundUpdate
		case downloadFailed
		case unknownError
		case testFailed
        case checksumFailed
        case downloadChecksumFailed
        case notFoundChecksums
        case apiRateLimit

		func des() -> String {
			switch self {
			case .decodeReleaseInfoFailed:
				return "Decode alpha release info failed"
			case .notFoundUpdate:
				return "Not found update"
			case .downloadFailed:
				return "Download failed"
			case .testFailed:
				return "Test downloaded file failed"
            case .checksumFailed:
                return "Checksum failed"
            case .downloadChecksumFailed:
                return "Download checksum failed"
            case .notFoundChecksums:
                return "Not found checksums.txt"
            case .apiRateLimit:
                return "API rate limit"
			case .unknownError:
				return "Unknown error"
			}
		}
	}

	struct ReleasesResp: Decodable {
		let assets: [Asset]
		struct Asset: Decodable {
			let name: String
			let downloadUrl: String
			let contentType: String
			let state: String

			enum CodingKeys: String, CodingKey {
				case name,
					 state,
					 downloadUrl = "browser_download_url",
					 contentType = "content_type"
			}
		}
	}

	static func assetName() -> String? {
		switch GetMachineHardwareName() {
		case "x86_64":
			return "amd64"
		case "arm64":
			return "arm64"
		default:
			return nil
		}
	}

	static func GetMachineHardwareName() -> String? {
		var sysInfo = utsname()
		let retVal = uname(&sysInfo)

		guard retVal == EXIT_SUCCESS else { return nil }

		let machineMirror = Mirror(reflecting: sysInfo.machine)
		let identifier = machineMirror.children.reduce("") { identifier, element in
			guard let value = element.value as? Int8, value != 0 else { return identifier }
			return identifier + String(UnicodeScalar(UInt8(value)))
		}
		return identifier
	}

	static func alphaAssets() async throws -> [ReleasesResp.Asset] {
        let url = "https://api.github.com/repos/MetaCubeX/mihomo/releases/tags/Prerelease-Alpha"
        let urlRequest = URLRequest(url: .init(string: url)!,
                                    cachePolicy: .reloadIgnoringCacheData)
        do {
            let (data, _) = try await URLSession.shared.data(for: urlRequest)
            if let msg = try? JSON(data: data)["message"].string {
                if msg.starts(with: "API rate limit") {
                    throw errors.apiRateLimit
                }
            }
            return try JSONDecoder().decode(ReleasesResp.self, from: data).assets
        } catch {
            throw errors.downloadFailed
        }
	}
    
    static func alphaCoreAsset(_ assets: [ReleasesResp.Asset]) async throws -> ReleasesResp.Asset {
        guard let assetName = assetName(),
              let asset = assets.first(where: {
                  guard $0.state == "uploaded", $0.contentType == "application/gzip" else { return false }
                  
                  let names = $0.name.split(separator: "-").map(String.init)
                  guard names.count > 4,
                        names[0] == "mihomo",
                        names[1] == "darwin",
                        names[2] == assetName,
                        names[3] == "alpha" else { return false }
                        
                  return true
              }) else {
            throw errors.decodeReleaseInfoFailed
        }
        
        return asset
    }
    
    static func checksumString(_ assets: [ReleasesResp.Asset], asset: ReleasesResp.Asset) async throws -> String {
        
        guard let checksumsAsset = assets.first(where: { $0.name == "checksums.txt" }),
              let url = URL(string: checksumsAsset.downloadUrl) else {
            throw errors.notFoundChecksums
        }
        
        do {
            let urlRequest = URLRequest(url: url, cachePolicy: .reloadIgnoringCacheData)
            let (data, _) = try await URLSession.shared.data(for: urlRequest)
            let str = String(data: data, encoding: .utf8)?
                .split(separator: "\n")
                .first(where: { $0.contains(asset.name) })?
                .split(separator: " ").first
            
            if let str {
                return String(str)
            } else {
                Logger.log("Decode checksums.txt failed", level: .debug)
                throw errors.downloadChecksumFailed
            }
        } catch {
            throw errors.downloadChecksumFailed
        }
    }
    
	static func checkVersion(_ asset: ReleasesResp.Asset) throws -> ReleasesResp.Asset {
		guard let path = Paths.alphaCorePath()?.path else {
			throw errors.unknownError
		}
		if let v = ClashProcess.verifyCoreFile(path),
		   asset.name.contains(v.version) {
			throw errors.notFoundUpdate
		}
		return asset
	}

	static func downloadCore(_ asset: ReleasesResp.Asset) async throws -> Data {
        do {
            let resp = try await HTTPClient.shared.execute(.init(url: asset.downloadUrl), timeout: .minutes(1))
            return try await resp.body.collectData()
        } catch {
            throw errors.downloadFailed
        }
	}

    static func replaceCore(_ gzData: Data, checksum: String) throws -> String {
		let fm = FileManager.default
        
        guard SHA256.hash(data: gzData).compactMap({ String(format: "%02x", $0) }).joined() == checksum else {
            throw errors.checksumFailed
        }

		guard let helperURL = Paths.alphaCorePath() else {
			throw errors.unknownError
		}

		try fm.createDirectory(at: helperURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)

		let cachePath = Paths.tempPath().appending("/\(UUID().uuidString).newcore")
		try gzData.gunzipped().write(to: .init(fileURLWithPath: cachePath))
		
		Logger.log("save alpha core in \(cachePath)")

		guard let version = ClashProcess.verifyCoreFile(cachePath)?.version else {
			throw errors.testFailed
		}

		try? fm.removeItem(at: helperURL)
		try fm.moveItem(atPath: cachePath, toPath: helperURL.path)

		return version
	}
}
