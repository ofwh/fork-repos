//
//  AlphaMetaDownloader.swift
//  ClashX Meta
//
//  Copyright © 2023 west2online. All rights reserved.
//

import Cocoa
import Alamofire
import CryptoKit

class AlphaMetaDownloader: NSObject {

	enum errors: Error {
		case decodeReleaseInfoFailed
		case notFoundUpdate
		case downloadFailed
		case unknownError
		case testFailed
        case checksumFailed
        case downloadChecksumFailed

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
		let resp = try? await AF.request("https://api.github.com/repos/MetaCubeX/mihomo/releases/tags/Prerelease-Alpha").serializingDecodable(ReleasesResp.self).value
		
		guard let resp else {
			throw errors.downloadFailed
		}
		
		return resp.assets
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
        guard let checksumsAsset = assets.first(where: {
            $0.name == "checksums.txt"
        }),
              let resp = try? await AF.request(checksumsAsset.downloadUrl).serializingString().value,
              let str = resp.split(separator: "\n").first(where: { $0.contains(asset.name) })?.split(separator: " ").first,
              str.count == 64
        else {
            throw errors.downloadChecksumFailed
        }
        
        return String(str)
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
		let fm = FileManager.default
		let data = try? await AF.download(asset.downloadUrl).serializingData().value

		if let data {
			return data
		} else {
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
