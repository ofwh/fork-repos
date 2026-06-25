//
//  MetaTask.swift
//  com.metacubex.ClashX.ProxyConfigHelper


import Cocoa

private actor MetaTaskStartSession {
	private var continuation: CheckedContinuation<String?, Never>?
	private var finished = false
	private var pollingTask: Task<Void, Never>?
	private var timeoutTask: Task<Void, Never>?
	private var logs = [String]()
	private var errorLogs = [String]()

	init(continuation: CheckedContinuation<String?, Never>) {
		self.continuation = continuation
	}

	func setPollingTask(_ task: Task<Void, Never>) {
		pollingTask = task
	}

	func setTimeoutTask(_ task: Task<Void, Never>) {
		timeoutTask = task
	}

	func appendLogs(_ items: [String]) {
		logs.append(contentsOf: items)
	}

	func appendErrorLogs(_ items: [String]) {
		errorLogs.append(contentsOf: items)
	}

	func logsString() -> String {
		logs.joined(separator: "\n")
	}

	func errorLogLines() -> [String] {
		errorLogs
	}

	func isFinished() -> Bool {
		finished
	}

	func finish(_ result: String?) {
		guard !finished else { return }
		finished = true
		pollingTask?.cancel()
		timeoutTask?.cancel()
		continuation?.resume(returning: result)
		continuation = nil
	}
}

class MetaTask: NSObject {
	private enum StartError: LocalizedError {
		case invalidConfig

		var errorDescription: String? {
			switch self {
			case .invalidConfig:
				return "Can't decode config file."
			}
		}
	}
    
    struct MetaCurl: Decodable {
        let hello: String
    }
    
    let proc = Process()

    func start(_ path: String,
                 confPath: String,
                 confFilePath: String,
                 confJSON: String) async -> String? {
        await withCheckedContinuation { continuation in
			let startSession = MetaTaskStartSession(continuation: continuation)
			Task {
				do {
					try await start(path,
								confPath: confPath,
								confFilePath: confFilePath,
								confJSON: confJSON,
								startSession: startSession)
				} catch let error as StartError {
					await startSession.finish(error.localizedDescription)
				} catch {
					await startSession.finish("Start meta error, \(error.localizedDescription).")
				}
			}
        }
    }
    
	private func start(_ path: String,
					 confPath: String,
					 confFilePath: String,
					 confJSON: String,
                       startSession: MetaTaskStartSession) async throws {
        
        proc.executableURL = .init(fileURLWithPath: path)
        proc.currentDirectoryURL = .init(fileURLWithPath: confPath)
        
        var args = [
            "-d",
            confPath
        ]
        
        if confFilePath != "" {
            args.append(contentsOf: [
                "-f",
                confFilePath
            ])
        }
        
		guard let confData = confJSON.data(using: .utf8),
		      let serverResult = try? JSONDecoder().decode(MetaServer.self, from: confData) else {
            throw StartError.invalidConfig
        }
        
        func encodeServerResult(with logs: String) -> String {
            var result = serverResult
            result.log = logs
            return result.jsonString()
        }
        
        var environment = ProcessInfo.processInfo.environment
        environment["SAFE_PATHS"] = serverResult.safePaths
        
        self.proc.environment = environment
        
        self.proc.arguments = args
        self.proc.qualityOfService = .userInitiated
        
        let pipe = Pipe()
        let errorPipe = Pipe()
        let outputStream = makeLineStream(from: pipe.fileHandleForReading)
        let errorStream = makeLineStream(from: errorPipe.fileHandleForReading)

        let outputTask = Task { [weak self] in
            guard let self else { return }

            for await rawMessages in outputStream {
                let messages = rawMessages.map(self.formatMsg)
                guard !messages.isEmpty else { continue }

                guard !(await startSession.isFinished()) else { continue }
                await startSession.appendLogs(messages)

                for message in messages {
                    if message.contains("External controller listen error:") || message.contains("External controller serve error:") {
                        await startSession.finish(message)
                        return
                    }

                    /*
                     if let range = $0.range(of: "RESTful API listening at: ") {
                     let addr = String($0[range.upperBound..<$0.endIndex])
                     guard addr.split(separator: ":").count == 2,
                     let port = Int(addr.split(separator: ":")[1]) else {
                     returnResult("Not found RESTful API port.")
                     return
                     }
                     let testLP = self.testListenPort(port)
                     if testLP.pid != 0,
                     testLP.pid == self.proc.processIdentifier,
                     testLP.addr == addr {
                     serverResult.log = logs.joined(separator: "\n")
                     returnResult(serverResult.jsonString())
                     } else {
                     returnResult("Check RESTful API pid failed.")
                     }
                     }
                     */

                    if message.contains("RESTful API listening at:") {
                        let controllerReady = await self.testExternalController(serverResult)
                        if controllerReady {
                            let logs = await startSession.logsString()
                            await startSession.finish(encodeServerResult(with: logs))
                        }
                    }
                }
            }
        }

        let errorTask = Task {
            for await messages in errorStream {
                guard !messages.isEmpty else { continue }
                await startSession.appendErrorLogs(messages)
            }
        }
        
        
        self.proc.standardError = errorPipe
        self.proc.standardOutput = pipe
        
        self.proc.terminationHandler = { proc in
            Task {
                _ = await outputTask.result
                _ = await errorTask.result

                if await startSession.isFinished() {
                    var errorLogs = await startSession.errorLogLines()
                    guard !errorLogs.isEmpty else { return }
                    
                    errorLogs.append("terminationStatus: \(proc.terminationStatus)")
                    errorLogs.append("terminationReason: \(proc.terminationReason)")
                    self.writeCrashLog(errorLogs, confPath: confPath)
                    return
                }
                
                let logs = await startSession.logsString()
                guard !logs.isEmpty else {
                    await startSession.finish("Meta process terminated, no found output.")
                    return
                }

                await startSession.finish(logs)
            }
        }
        
        try self.proc.run()
        
        let pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(seconds: 0.5)
                guard !Task.isCancelled else { return }
                guard await self.testExternalController(serverResult) else { continue }
                
                let logs = await startSession.logsString()
                await startSession.finish(encodeServerResult(with: logs))
                return
            }
        }
        let timeoutTask = Task {
            try? await Task.sleep(seconds: 30)
            guard !Task.isCancelled else { return }
            let logs = await startSession.logsString()
            await startSession.finish(encodeServerResult(with: logs))
        }
        
        await startSession.setPollingTask(pollingTask)
        await startSession.setTimeoutTask(timeoutTask)
        
    }

    private func makeLineStream(from fileHandle: FileHandle) -> AsyncStream<[String]> {
        AsyncStream { continuation in
            var buffer = Data()

            func decodeLines(flushRemainder: Bool) -> [String] {
                var lines = [String]()

                while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer.prefix(upTo: newlineIndex)
                    buffer.removeSubrange(buffer.startIndex...newlineIndex)

                    guard let line = String(data: lineData, encoding: .utf8), !line.isEmpty else {
                        continue
                    }

                    lines.append(line)
                }

                if flushRemainder,
                   !buffer.isEmpty,
                   let line = String(data: buffer, encoding: .utf8),
                   !line.isEmpty {
                    lines.append(line)
                    buffer.removeAll(keepingCapacity: false)
                }

                return lines
            }

            fileHandle.readabilityHandler = { handle in
                let data = handle.availableData

                if data.isEmpty {
                    let lines = decodeLines(flushRemainder: true)
                    if !lines.isEmpty {
                        continuation.yield(lines)
                    }
                    handle.readabilityHandler = nil
                    continuation.finish()
                    return
                }

                buffer.append(data)
                let lines = decodeLines(flushRemainder: false)

                if !lines.isEmpty {
                    continuation.yield(lines)
                }
            }

            continuation.onTermination = { _ in
                fileHandle.readabilityHandler = nil
            }
        }
    }

	private func writeCrashLog(_ errorLogs: [String], confPath: String) {
		let data = errorLogs.joined(separator: "\n").data(using: .utf8)
		let url = URL(fileURLWithPath: confPath).appendingPathComponent("logs")
		let fm = FileManager.default
		try? fm.createDirectory(atPath: url.path, withIntermediateDirectories: true)

		let fileName = {
			let dateformat = DateFormatter()
			dateformat.dateFormat = "yyyy-MM-dd_HH-mm-ss"
			let s = dateformat.string(from: Date())
			return "meta_core_crash_\(s).log"
		}()

		fm.createFile(atPath: url.appendingPathComponent(fileName).path, contents: data)
	}

    func stop() async {
		guard proc.isRunning else { return }
        await Command(cmd: "/bin/kill", args: ["-9", "\(self.proc.processIdentifier)"]).run()
	}
    

    @discardableResult
    func terminateExistingMeta() async -> Bool {
		let pids = await Command(cmd: "/usr/bin/pgrep", args: ["-x", "com.metacubex.ClashX.ProxyConfigHelper.meta"]).run()
        _ = await Command(cmd: "/usr/bin/killall", args: ["com.metacubex.ClashX.ProxyConfigHelper.meta"]).run()
        return !pids.isEmpty
    }
    
	func getUsedPorts() async -> String? {
		let output = await Command(cmd: "/bin/bash", args: ["-c", "lsof -nP -iTCP -sTCP:LISTEN | grep LISTEN"]).run()
		guard !output.isEmpty else {
			return ""
		}

		return output.split(separator: "\n").compactMap { str -> Int? in
			let line = str.split(separator: " ").map(String.init)
			guard line.count == 10,
			let port = line[8].components(separatedBy: ":").last else { return nil }
			return Int(port)
		}.map(String.init).joined(separator: ",")
	}
    
    func testListenPort(_ port: Int) async -> (pid: Int32, addr: String) {
        let output = await Command(cmd: "/bin/bash", args: ["-c", "lsof -nP -iTCP:\(port) -sTCP:LISTEN | grep LISTEN"]).run()
        let fields = output.split(separator: " ").map(String.init)
        guard fields.count == 10 else {
            return (0, "")
        }

        let pid = fields[1]
        let addr = fields[8]
        
        return (Int32(pid) ?? 0, addr)
    }
    
    func testExternalController(_ server: MetaServer) async -> Bool {
        var args = [server.externalController]
        if server.secret != "" {
            args.append(contentsOf: [
                "--header",
                "Authorization: Bearer \(server.secret)"
            ])
        }

		guard let data = try? await Command(cmd: "/usr/bin/curl", args: args).outputData(),
			  let str = try? JSONDecoder().decode(MetaCurl.self, from: data),
			  (str.hello == "clash.meta" || str.hello == "mihomo") else {
            return false
        }
        return true
    }
    
    func formatMsg(_ msg: String) -> String {
        let msgs = msg.split(separator: " ", maxSplits: 2).map(String.init)
        
        guard msgs.count == 3,
              msgs[1].starts(with: "level"),
              msgs[2].starts(with: "msg") else {
            return msg
        }
        
        let level = msgs[1].replacingOccurrences(of: "level=", with: "")
        var re = msgs[2].replacingOccurrences(of: "msg=\"", with: "")
        
        while re.last == "\"" || re.last == "\n" {
            re.removeLast()
        }
        
        if re.contains("time=") {
            print(re)
        }
        
        return "[\(level)] \(re)"
    }
    
    func parseConfFile(_ confPath: String, confFilePath: String) -> MetaServer? {
        let fileURL = confFilePath == "" ? URL(fileURLWithPath: confPath).appendingPathComponent("config.yaml", isDirectory: false) : URL(fileURLWithPath: confFilePath)
        
        guard let data = FileManager.default.contents(atPath: fileURL.path),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }
        let lines = content.split(separator: "\n").map(String.init)
        
        func find(_ key: String) -> String {
            var re = lines.first(where: { $0.starts(with: "\(key): ") })?.dropFirst("\(key): ".count) ?? ""
            
            if re.hasPrefix("\"") && re.hasSuffix("\"")
                || re.hasPrefix("'") && re.hasSuffix("'") {
                re.removeLast()
                re.removeFirst()
            }
            return String(re)
        }
        
        return MetaServer(externalController: find("external-controller"),
                          secret: find("secret"))
    }
}
