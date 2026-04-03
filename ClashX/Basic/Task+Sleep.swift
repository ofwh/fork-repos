//
//  Task+Sleep.swift
//  ClashX
//

import Foundation

public extension Task where Success == Never, Failure == Never {
    static func sleep(seconds: TimeInterval) async throws {
        try await sleep(nanoseconds: UInt64((seconds * 1_000_000_000).rounded()))
    }
}