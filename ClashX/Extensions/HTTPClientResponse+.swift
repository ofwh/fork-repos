//
//  HTTPClientResponse+.swift
//  ClashX Meta
//
//  Copyright © 2026 west2online. All rights reserved.
//

import AsyncHTTPClient
import NIOCore
import Foundation

public extension HTTPClientResponse.Body {
    /// Collect the entire body into Data.
    /// If `limit` is provided, uses `collect(upTo:)` fast-path; otherwise iterates the async sequence.
    func collectData(upTo limit: Int? = nil) async throws -> Data {
        if let limit = limit {
            let buffer = try await self.collect(upTo: limit)
            return Data(buffer.readableBytesView)
        } else {
            var data = Data()
            for try await chunk in self {
                data.append(contentsOf: chunk.readableBytesView)
            }
            return data
        }
    }

    /// Collect the entire body and return a String.
    /// Default encoding is UTF-8; returns empty string if decoding fails.
    func collectString(encoding: String.Encoding = .utf8, upTo limit: Int? = nil) async throws -> String {
        let data = try await collectData(upTo: limit)
        if encoding == .utf8 {
            // UTF-8 fast path which won't fail
            return String(decoding: data, as: UTF8.self)
        } else {
            return String(data: data, encoding: encoding) ?? ""
        }
    }
}
