//
//  Logger.swift
//  ClashX
//
//  Created by CYC on 2018/8/7.
//  Copyright © 2018年 yichengchen. All rights reserved.
//

import CocoaLumberjackSwift
import Foundation

private class AppLogFileManager: DDLogFileManagerDefault {
    override var newLogFileName: String {
        let df = DateFormatter()
        df.dateFormat = "dd_HH-mm-ss"
        return "clashx_\(df.string(from: Date())).log"
    }

    override func isLogFile(withName fileName: String) -> Bool {
        fileName.range(of: #"^clashx_\d{2}_\d{2}-\d{2}-\d{2}\.log$"#, options: .regularExpression) != nil
    }
}

class Logger {
    static let shared = Logger()
    var fileLogger: DDFileLogger = .init()
    private(set) var sessionId = ""
    
    private var cleanupLogTask: Task<Void, Never>?

    var coreLogPath: String {
        "\(logFolder())/\(kCoreLogName)"
    }

    var coreCrashLogPath: String {
        "\(logFolder())/\(kCoreCrashLogName)"
    }

    private init() {
        #if DEBUG
            DDLog.add(DDOSLogger.sharedInstance)
        #endif
        dynamicLogLevel = ConfigManager.selectLoggingApiLevel.toDDLogLevel()
    }

    func configure(logDirectory: String, sessionId: String) {
        self.sessionId = sessionId
        let dateFormatter = DateFormatter()
        dateFormatter.setLocalizedDateFormatFromTemplate("YYYY/MM/dd HH:mm:ss:SSS")
        let fm = AppLogFileManager(logsDirectory: logDirectory)
        let newLogger = DDFileLogger(logFileManager: fm)
        newLogger.logFormatter = DDLogFileFormatterDefault(dateFormatter: dateFormatter)
        newLogger.rollingFrequency = TimeInterval(60 * 60 * 24) // 24 hours
        newLogger.maximumFileSize = 5 * 1024 * 1024 // 5MB
        newLogger.logFileManager.maximumNumberOfLogFiles = 3
        DDLog.remove(fileLogger)
        fileLogger = newLogger
        DDLog.add(newLogger)
        
        startCleanup()
    }

    private func logToFile(msg: String, level: ClashLogLevel) {
        switch level {
        case .debug, .silent:
            DDLogDebug(DDLogMessageFormat(stringLiteral: msg))
        case .error:
            DDLogError(DDLogMessageFormat(stringLiteral: msg))
        case .info:
            DDLogInfo(DDLogMessageFormat(stringLiteral: msg))
        case .warning:
            DDLogWarn(DDLogMessageFormat(stringLiteral: msg))
        case .unknow:
            DDLogWarn(DDLogMessageFormat(stringLiteral: msg))
        }
    }

    static func log(_ msg: String, level: ClashLogLevel = .info, file: String = #file, function: String = #function) {
		let fileName = URL(fileURLWithPath: file).lastPathComponent
        shared.logToFile(msg: "[\(level.rawValue)] \(fileName) \(function) \(msg)", level: level)
    }

    func logFilePath() -> String {
        return fileLogger.logFileManager.sortedLogFilePaths.first ?? ""
    }

    func logFolder() -> String {
        return fileLogger.logFileManager.logsDirectory
    }

    func setupLogSession() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let sessionId = dateFormatter.string(from: Date())

        let logsDir = "\(kConfigFolderPath)logs/\(sessionId)"
        try? FileManager.default.createDirectory(atPath: logsDir, withIntermediateDirectories: true)

        configure(logDirectory: logsDir, sessionId: sessionId)

        FileManager.default.createFile(atPath: coreLogPath, contents: nil)
        FileManager.default.createFile(atPath: coreCrashLogPath, contents: nil)

        cleanupLogDirectories()
    }
    

    private func cleanupLogDirectories() {
        let logsRoot = "\(kConfigFolderPath)logs/"
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: logsRoot) else { return }

        let maxCount = 20
        let sorted = contents
            .filter { $0.contains("-") }
            .sorted(by: >)

        guard sorted.count > maxCount else { return }

        for name in sorted[maxCount...] {
            try? FileManager.default.removeItem(atPath: "\(logsRoot)\(name)")
        }
    }
    
    
    func startCleanup() {
        cleanupLogTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(seconds: 5 * 60)
                try? FileHandle(forWritingTo: URL(fileURLWithPath: coreLogPath)).truncate(atOffset: 0)
            }
        }
    }
}
