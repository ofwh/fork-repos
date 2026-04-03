//
//  Command.swift
//  ClashX
//
//  Created by yicheng on 2023/10/13.
//  Copyright © 2023 west2online. All rights reserved.
//

import Foundation

struct Command {
    let cmd: String
    let args: [String]

    @discardableResult
    func run() async -> String {
        do {
            let output = try await outputData()
            return String(data: output, encoding: .utf8)?.trimmingCharacters(in: .newlines) ?? ""
        } catch {
            print("Error running command: \(error)")
            return ""
        }
    }

    func outputData() async throws -> Data {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: cmd)
        task.arguments = args

        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = Pipe()

        return try await withCheckedThrowingContinuation { continuation in
            task.terminationHandler = { _ in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: outputData)
            }

            do {
                try task.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
