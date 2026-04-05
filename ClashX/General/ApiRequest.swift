//
//  ApiRequest.swift
//  ClashX
//
//  Created by CYC on 2018/7/30.
//  Copyright © 2018年 yichengchen. All rights reserved.
//

import Alamofire
import Cocoa
import Starscream
import SwiftyJSON

protocol ApiRequestStreamDelegate: AnyObject {
    func didUpdateTraffic(up: Int, down: Int) async
    func didGetLog(log: String, level: String) async
    func didUpdateMemory(memory: Int64) async
    func streamStatusChanged() async
}

typealias ErrorString = String

struct ClashVersion: Decodable {
	let version: String
	let meta: Bool?
}

class ApiRequest {
    static let shared = ApiRequest()

    private var proxyRespCache: ClashProxyResp?

    private lazy var logQueue = DispatchQueue(label: "com.ClashX.core.log")

    @objc enum ProviderType: Int {
        case rule, proxy

        func apiString() -> String {
            self == .proxy ? "proxies" : "rules"
        }

        func logString() -> String {
            self == .proxy ? "Proxy" : "Rule"
        }
    }

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 604800
        configuration.timeoutIntervalForResource = 604800
        configuration.httpMaximumConnectionsPerHost = 100
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        alamoFireManager = Session(configuration: configuration)
    }

    static func authHeader() -> HTTPHeaders {
        let secret = ConfigManager.shared.overrideSecret ?? ConfigManager.shared.apiSecret
        return (!secret.isEmpty) ? ["Authorization": "Bearer \(secret)"] : [:]
    }

    @discardableResult
    private static func req(
        _ url: String,
        method: HTTPMethod = .get,
        parameters: Parameters? = nil,
        encoding: ParameterEncoding = URLEncoding.default,
        requiresCoreRunning: Bool = true
    ) -> DataRequest {
        guard !requiresCoreRunning || ConfigManager.shared.isRunning else {
            return AF.request("")
        }

        return shared.alamoFireManager
            .request(ConfigManager.apiUrl + url,
                     method: method,
                     parameters: parameters,
                     encoding: encoding,
                     headers: authHeader())
    }

    static func findConfigPath(configName: String) async -> String? {
        if ICloudManager.shared.useiCloud.value {
            guard let url = await ICloudManager.shared.getUrl() else {
                return nil
            }
            return url.appendingPathComponent(Paths.configFileName(for: configName)).path
        } else {
            return Paths.localConfigPath(for: configName)
        }
    }

    private static func flushFakeipCacheResult() async -> Bool {
        Logger.log("FlushFakeipCache")

        let success: Bool

        let response = await req("/cache/fakeip/flush", method: .post)
            .serializingData()
            .response
        success = response.response?.statusCode == 204

        Logger.log("FlushFakeipCache \(success ? "success" : "failed")")
        return success
    }

    private static func flushDNSCacheResult() async -> Bool {
        Logger.log("FlushDNSCache")

        let success: Bool

        let response = await req("/cache/dns/flush", method: .post)
            .serializingData()
            .response
        success = response.response?.statusCode == 204

        Logger.log("FlushDNSCache \(success ? "success" : "failed")")
        return success
    }

    weak var delegate: ApiRequestStreamDelegate?
	weak var dashboardDelegate: ApiRequestStreamDelegate?

	private var trafficWebSocket: WebSocket?
	private var loggingWebSocket: WebSocket?
	private var memoryWebSocket: WebSocket?

	private var trafficWebSocketRetryDelay: TimeInterval = 1
	private var loggingWebSocketRetryDelay: TimeInterval = 1
	private var memoryWebSocketRetryDelay: TimeInterval = 1
	
    private var trafficWebSocketRetryTask: Task<Void, Never>?
    private var loggingWebSocketRetryTask: Task<Void, Never>?
    private var memoryWebSocketRetryTask: Task<Void, Never>?
    
    private var logRateLimiter = LogRateLimiter {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Log system crashed.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Quit", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSApplication.shared.terminate(nil)
        }
    }

	private var alamoFireManager: Session

	static func requestVersion() async -> ClashVersion? {
		do {
			return try await req("/version", requiresCoreRunning: false)
				.validate()
				.serializingDecodable(ClashVersion.self)
				.value
		} catch {
			Logger.log("Request Version failed, \(error)", level: .error)
			return nil
		}
	}

    static func requestConfig() async -> ClashConfig? {
        do {
            return try await req("/configs")
                .validate()
                .serializingDecodable(ClashConfig.self)
                .value
        } catch {
            Logger.log(error.localizedDescription)
            await MainActor.run {
                UserNotificationCenter.shared.post(title: "Error", info: error.localizedDescription)
            }
            return nil
        }
    }

    static func requestConfigUpdate(configName: String) async -> ErrorString? {
        guard let path = await findConfigPath(configName: configName) else {
            return "icloud error"
        }

        guard ICloudManager.shared.useiCloud.value else {
            return await requestConfigUpdate(configPath: path)
        }

        #warning("icloud operation not permitted")

        let tempPath = Paths.localConfigPath(for: kSafeConfigName)

        try? FileManager.default.removeItem(atPath: tempPath)

        do {
            try FileManager.default.copyItem(atPath: path, toPath: tempPath)
        } catch {
            return "clashx_meta_config error \(error)"
        }

        return await requestConfigUpdate(configPath: tempPath)
    }

    static func requestConfigUpdate(configPath: String) async -> ErrorString? {
        let placeHolderErrorDesp = "Error occoured, Please try to fix it by restarting ClashX. "

        let response = await req(
                "/configs",
                method: .put,
                parameters: ["Path": configPath],
                encoding: JSONEncoding.default
            )
            .serializingData()
            .response

        if response.response?.statusCode == 204 {
            ConfigManager.shared.isRunning = true
            return nil
        }

        let err = JSON(response.data ?? Data())["message"].string
            ?? response.error?.localizedDescription
            ?? placeHolderErrorDesp
        Logger.log(err)
        return err
    }

    static func updateOutBoundMode(mode: ClashProxyMode) async -> Bool {
        do {
            _ = try await req(
                "/configs",
                method: .patch,
                parameters: ["mode": mode.rawValue],
                encoding: JSONEncoding.default
            )
            .validate()
            .serializingData()
            .value
            return true
        } catch {
            return false
        }
    }

    static func updateLogLevel(level: ClashLogLevel) async -> Bool {
        do {
            _ = try await req(
                "/configs",
                method: .patch,
                parameters: ["log-level": level.rawValue],
                encoding: JSONEncoding.default
            )
            .validate()
            .serializingData()
            .value
            return true
        } catch {
            return false
        }
    }

    static func requestProxyGroupList() async -> ClashProxyResp {
        let proxies: ClashProxyResp

        do {
            let responseData = try await req("/proxies")
                .validate()
                .serializingData()
                .value
            proxies = ClashProxyResp(responseData)
        } catch {
            Logger.log(error.localizedDescription)
            proxies = ClashProxyResp(nil)
        }

        ApiRequest.shared.proxyRespCache = proxies
        return proxies
    }

    static func requestProxyProviderList() async -> ClashProviderResp {
        do {
            return try await req("/providers/proxies")
                .validate()
                .serializingDecodable(ClashProviderResp.self, decoder: ClashProviderResp.decoder)
                .value
        } catch {
            Logger.log("requestProxyProviderList error \(error.localizedDescription)")
            return ClashProviderResp()
        }
    }

    static func getAllProxyList() async -> [ClashProxyName] {
        let proxyInfo = await requestProxyGroupList()
        return proxyInfo.proxiesMap["GLOBAL"]?.all ?? []
    }

    static func updateAllowLan(allow: Bool) async {
        Logger.log("update allow lan:\(allow)", level: .debug)
        do {
            _ = try await req(
                "/configs",
                method: .patch,
                parameters: ["allow-lan": allow],
                encoding: JSONEncoding.default
            )
            .validate()
            .serializingData()
            .value
        } catch {
            Logger.log("update allow lan failed: \(error.localizedDescription)", level: .error)
        }
    }

    static func updateProxyGroup(group: String, selectProxy: String) async -> Bool {
        let response = await req(
            "/proxies/\(group.encoded)",
            method: .put,
            parameters: ["name": selectProxy],
            encoding: JSONEncoding.default
        )
        .serializingData()
        .response
        return response.response?.statusCode == 204
    }

    static func getMergedProxyData() async -> ClashProxyResp {
        async let provider = requestProxyProviderList()
        async let proxyInfo = requestProxyGroupList()

        let mergedProxyInfo = await proxyInfo
        mergedProxyInfo.updateProvider(await provider)
        return mergedProxyInfo
    }

    static func getProxyDelay(proxyName: String) async -> Int {
        do {
            let responseData = try await req(
                "/proxies/\(proxyName.encoded)/delay",
                method: .get,
                parameters: ["timeout": 2500, "url": ConfigManager.shared.benchMarkUrl]
            )
            .validate()
            .serializingData()
            .value
            return JSON(responseData)["delay"].intValue
        } catch {
            return 0
        }
    }

    static func getGroupDelay(groupName: String) async -> [String: Int] {
        do {
            let responseData = try await req(
                "/group/\(groupName.encoded)/delay",
                method: .get,
                parameters: ["timeout": 2500, "url": ConfigManager.shared.benchMarkUrl]
            )
            .validate()
            .serializingData()
            .value
            return (try? JSONDecoder().decode([String: Int].self, from: responseData)) ?? [:]
        } catch {
            return [:]
        }
    }

    static func getRules() async -> [ClashRule] {
        do {
            let responseData = try await req("/rules")
                .validate()
                .serializingData()
                .value
            return ClashRuleResponse.fromData(responseData).rules ?? []
        } catch {
            return []
        }
    }

    static func healthCheck(proxy: ClashProviderName) async {
        Logger.log("HeathCheck for \(proxy) started")
        let response = await req("/providers/proxies/\(proxy.encoded)/healthcheck")
            .serializingData()
            .response
        if response.response?.statusCode == 204 {
            Logger.log("HeathCheck for \(proxy) finished")
        } else {
            Logger.log("HeathCheck for \(proxy) failed:\(response.response?.statusCode ?? -1)")
        }
    }
}

// MARK: - Connections

extension ApiRequest {
    static func getConnections() async -> [ClashConnectionBaseSnapShot.Connection] {
        do {
            let snapshot = try await req("/connections")
                .validate()
                .serializingDecodable(ClashConnectionBaseSnapShot.self)
                .value
            return snapshot.connections
        } catch {
            assertionFailure()
            return []
        }
    }

    static func closeConnection(_ id: String) async {
        _ = try? await req("/connections/\(id)", method: .delete)
            .validate()
            .serializingData()
            .value
    }
	
	static func getConnectionsSnapshot() async -> DBConnectionSnapShot? {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .formatted(DateFormatter.js)
		
		do {
			return try await req("/connections")
				.validate()
				.serializingDecodable(DBConnectionSnapShot.self, decoder: decoder)
				.value
		} catch {
			return nil
		}
	}

	static func closeConnection(_ conn: ClashConnectionSnapShot.Connection) async {
		_ = try? await req("/connections/".appending(conn.id), method: .delete)
			.validate()
			.serializingData()
			.value
	}

	static func closeAllConnection() async {
		_ = try? await req("/connections", method: .delete)
			.validate()
			.serializingData()
			.value
	}
}

// MARK: - Meta

extension ApiRequest {
    static func updateAllProviders(for type: ProviderType) async -> Int {
        let providerNames: [String]

        if type == .proxy {
            let response = await requestProxyProviderList()
            providerNames = response.allProviders
                .filter { $0.value.vehicleType == .HTTP }
                .map(\.key)
        } else {
            let response = await requestRuleProviderList()
            providerNames = response.allProviders.map(\.key)
        }

        return await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for name in providerNames {
                group.addTask {
                    await !updateProvider(for: type, name: name)
                }
            }

            var failuresCount = 0
            for await didFail in group {
                if didFail {
                    failuresCount += 1
                }
            }
            return failuresCount
        }
    }

    static func updateProvider(for type: ProviderType, name: String) async -> Bool {
        let logTitle = "Update \(type.logString()) Provider"

        Logger.log("\(logTitle) \(name)")

        let response = await req("/providers/\(type.apiString())/\(name)", method: .put)
            .serializingData()
            .response
        let success = response.response?.statusCode == 204

        Logger.log("\(logTitle) \(name) \(success ? "success" : "failed")")
        return success
    }

    static func requestRuleProviderList() async -> ClashRuleProviderResp {
        do {
            return try await req("/providers/rules")
                .validate()
                .serializingDecodable(ClashRuleProviderResp.self, decoder: ClashProviderResp.decoder)
                .value
        } catch {
            Logger.log("Get Rule providers error \(error.localizedDescription)")
            return ClashRuleProviderResp()
        }
    }

    static func flushDNSCache() async {
        async let flushFakeipCache = flushFakeipCacheResult()
        async let flushDNSCache = flushDNSCacheResult()

        let flushFakeipCacheResult = await flushFakeipCache
        let flushDNSCacheResult = await flushDNSCache
        let info = (flushFakeipCacheResult && flushDNSCacheResult) ? "Success" : "Failed"

        await MainActor.run {
            UserNotificationCenter.shared.post(title: NSLocalizedString("Flush dns cache", comment: ""), info: info)
        }
    }

    static func updateGEO() async -> Bool {
        Logger.log("UpdateGEO")
        let response = await req("/configs/geo", method: .post)
            .serializingData()
            .response
        let success = response.response?.statusCode == 204
        Logger.log("Updating GEO Databases...")
        return success
    }

    static func updateTun(enable: Bool) async {
        Logger.log("update tun:\(enable)", level: .debug)
        do {
            _ = try await req(
                "/configs",
                method: .patch,
                parameters: ["tun": ["enable": enable]],
                encoding: JSONEncoding.default
            )
            .validate()
            .serializingData()
            .value
        } catch {
            Logger.log("update tun failed: \(error.localizedDescription)", level: .error)
        }
    }

    static func updateSniffing(enable: Bool) async {
        Logger.log("update sniffing:\(enable)", level: .debug)
        do {
            _ = try await req(
                "/configs",
                method: .patch,
                parameters: ["sniffing": enable],
                encoding: JSONEncoding.default
            )
            .validate()
            .serializingData()
            .value
        } catch {
            Logger.log("update sniffing failed: \(error.localizedDescription)", level: .error)
        }
    }
    
    // MARK: - Providers

    struct AllProviders {
        var proxies = [String]()
        var rules = [String]()
    }

    static func requestExternalProviderNames() async -> AllProviders {
        async let proxyNamesTask: [String] = {
            do {
                let responseData = try await req("/providers/proxies")
                    .validate()
                    .serializingData()
                    .value
                let json = JSON(responseData)
                return json["providers"].dictionaryValue
                    .filter { $0.value["vehicleType"] == "HTTP" }
                    .map(\.key)
            } catch {
                Logger.log(error.localizedDescription, level: .warning)
                return []
            }
        }()


        return AllProviders(proxies: await proxyNamesTask, rules: [])
    }

	/*
    enum ProviderType {
        case proxy
        case rule
    }
	 */

    static func resetFakeIpCache() async {
        let response = await req("/cache/fakeip/flush", method: .post)
            .serializingData()
            .response
        Logger.log("flush fake ip: \(response.response?.statusCode ?? -1)")
    }
}

// MARK: - Stream Apis

extension ApiRequest {
	func resetStreamApis() {
		resetLogStreamApi()
		resetTrafficStreamApi()
		resetMemoryStreamApi()
	}

    func resetLogStreamApi() {
        cancelLoggingRetryTask()
        loggingWebSocketRetryDelay = 1
        requestLog()
    }

    func resetTrafficStreamApi() {
        cancelTrafficRetryTask()
        trafficWebSocketRetryDelay = 1
        requestTrafficInfo()
    }
	
	func resetMemoryStreamApi() {
		cancelMemoryRetryTask()
		memoryWebSocketRetryDelay = 1
		requestMemoryInfo()
	}

    private func requestTrafficInfo() {
        cancelTrafficRetryTask()
        trafficWebSocket?.disconnect(forceTimeout: 0.5)

        let socket = WebSocket(url: URL(string: ConfigManager.apiUrl.appending("/traffic"))!)

        for header in ApiRequest.authHeader() {
            socket.request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        socket.delegate = self
        socket.connect()
        trafficWebSocket = socket
    }

    private func requestLog() {
        cancelLoggingRetryTask()
        loggingWebSocket?.disconnect(forceTimeout: 1)

        let uriString = "/logs?level=".appending(ConfigManager.selectLoggingApiLevel.rawValue)
        let socket = WebSocket(url: URL(string: ConfigManager.apiUrl.appending(uriString))!)
        for header in ApiRequest.authHeader() {
            socket.request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        socket.delegate = self
        socket.callbackQueue = logQueue
        socket.connect()
        loggingWebSocket = socket
    }
	
	private func requestMemoryInfo() {
        cancelMemoryRetryTask()
		memoryWebSocket?.disconnect(forceTimeout: 1)
		
		let socket = WebSocket(url: URL(string: ConfigManager.apiUrl.appending("/memory"))!)
		for header in ApiRequest.authHeader() {
			socket.request.setValue(header.value, forHTTPHeaderField: header.name)
		}
		socket.delegate = self
		socket.connect()
		memoryWebSocket = socket
	}

    private func notifyStreamStatusChanged() async {
        await delegate?.streamStatusChanged()
        await dashboardDelegate?.streamStatusChanged()
    }

    private func notifyTrafficUpdate(up: Int, down: Int) async {
        await delegate?.didUpdateTraffic(up: up, down: down)
        await dashboardDelegate?.didUpdateTraffic(up: up, down: down)
    }

    private func notifyLog(log: String, level: String) async {
        await delegate?.didGetLog(log: log, level: level)
        await dashboardDelegate?.didGetLog(log: log, level: level)
    }

    private func notifyMemoryUpdate(memory: Int64) async {
        await delegate?.didUpdateMemory(memory: memory)
        await dashboardDelegate?.didUpdateMemory(memory: memory)
    }

    private func cancelTrafficRetryTask() {
        trafficWebSocketRetryTask?.cancel()
        trafficWebSocketRetryTask = nil
    }

    private func cancelLoggingRetryTask() {
        loggingWebSocketRetryTask?.cancel()
        loggingWebSocketRetryTask = nil
    }

	private func cancelMemoryRetryTask() {
		memoryWebSocketRetryTask?.cancel()
		memoryWebSocketRetryTask = nil
    }

    private func scheduleTrafficRetry() {
        let retryDelay = trafficWebSocketRetryDelay
        cancelTrafficRetryTask()
        trafficWebSocketRetryTask = Task { [weak self] in
            try? await Task.sleep(seconds: retryDelay)
            guard let self, !Task.isCancelled else { return }
            if self.trafficWebSocket?.isConnected == true { return }
            self.requestTrafficInfo()
        }
        trafficWebSocketRetryDelay *= 2
    }

    private func scheduleLoggingRetry() {
        let retryDelay = loggingWebSocketRetryDelay
        cancelLoggingRetryTask()
        loggingWebSocketRetryTask = Task { [weak self] in
            try? await Task.sleep(seconds: retryDelay)
            guard let self, !Task.isCancelled else { return }
            if self.loggingWebSocket?.isConnected == true { return }
            self.requestLog()
        }
        loggingWebSocketRetryDelay *= 2
    }

	private func scheduleMemoryRetry() {
		let retryDelay = memoryWebSocketRetryDelay
        cancelMemoryRetryTask()
		memoryWebSocketRetryTask = Task { [weak self] in
			try? await Task.sleep(seconds: retryDelay)
			guard let self, !Task.isCancelled else { return }
			if self.memoryWebSocket?.isConnected == true { return }
			self.requestMemoryInfo()
		}
		memoryWebSocketRetryDelay *= 2
	}
}

extension ApiRequest: WebSocketDelegate {
	func websocketDidConnect(socket: WebSocketClient) {
		guard let webSocket = socket as? WebSocket else { return }
		switch webSocket {
		case trafficWebSocket:
			trafficWebSocketRetryDelay = 1
			Logger.log("trafficWebSocket did Connect", level: .debug)
			
			ConfigManager.shared.isRunning = true
            Task {
                await notifyStreamStatusChanged()
            }
		case loggingWebSocket:
			loggingWebSocketRetryDelay = 1
			Logger.log("loggingWebSocket did Connect", level: .debug)
		case memoryWebSocket:
			memoryWebSocketRetryDelay = 1
			Logger.log("memoryWebSocket did Connect", level: .debug)
		default:
			return
		}
	}

	func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
		
		if (socket as? WebSocket) == trafficWebSocket {
			ConfigManager.shared.isRunning = false
            Task {
                await notifyStreamStatusChanged()
            }
		}
		
		guard let err = error else {
			return
		}

		Logger.log(err.localizedDescription, level: .error)

		guard let webSocket = socket as? WebSocket else { return }

		switch webSocket {
		case trafficWebSocket:
			Logger.log("trafficWebSocket did disconnect", level: .debug)
            scheduleTrafficRetry()
		case loggingWebSocket:
			Logger.log("loggingWebSocket did disconnect", level: .debug)
            scheduleLoggingRetry()
		case memoryWebSocket:
			Logger.log("memoryWebSocket did disconnect", level: .debug)
            scheduleMemoryRetry()
		default:
			return
		}
	}

	func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
		guard let webSocket = socket as? WebSocket else { return }
		let json = JSON(parseJSON: text)
		
		
		switch webSocket {
		case trafficWebSocket:
            Task {
                await notifyTrafficUpdate(up: json["up"].intValue, down: json["down"].intValue)
            }
		case loggingWebSocket:
            Task {
                guard await logRateLimiter.processLog() else { return }
                await notifyLog(log: json["payload"].stringValue, level: json["type"].string ?? "info")
            }
		case memoryWebSocket:
            Task {
                await notifyMemoryUpdate(memory: json["inuse"].int64Value)
            }
		default:
			return
		}
	}

	func websocketDidReceiveData(socket: WebSocketClient, data: Data) {}
}
