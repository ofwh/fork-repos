import Foundation

actor LogRateLimiter {
    private let maxLogsCount: Int = 20000
    private let timeDuration: TimeInterval = 5.0
    private var logCount: Int = 0
    private var startTime: TimeInterval = CFAbsoluteTimeGetCurrent()
    private var lastTimeCheck: TimeInterval = CFAbsoluteTimeGetCurrent()
    private var isBlocked = false
    
    private let onRateLimitTriggered: () -> Void
    
    init(onRateLimitTriggered: @escaping () -> Void) {
        self.onRateLimitTriggered = onRateLimitTriggered
    }
    
    // Returns true if log can be processed, false if rate limited
    func processLog() -> Bool {
        guard !isBlocked else { return false }
        
        let now = CFAbsoluteTimeGetCurrent()
        
        // Only check time and count every 1 second to reduce overhead
        if now - lastTimeCheck >= 1.0 {
            lastTimeCheck = now
            
            // Reset counter if time window has passed
            if now - startTime >= timeDuration {
                startTime = now
                logCount = 0
            }
            
            // Check if rate limit exceeded
            if logCount >= maxLogsCount {
                Task { await triggerRateLimit() }
                return false
            }
        }
        
        logCount += 1
        return true
    }
    
    private func triggerRateLimit() async {
        isBlocked = true
        
        // Execute callback on main actor
        await MainActor.run {
            onRateLimitTriggered()
            Logger.log("⚠️ Rate limit triggered: >\(maxLogsCount) logs/\(timeDuration)sec, paused for 1min")
        }
        
        // Resume after 60 seconds
        try? await Task.sleep(seconds: 60)
        
        isBlocked = false
        
        await MainActor.run {
            Logger.log("✅ Rate limit resumed")
        }
    }
}
