import Dispatch
import Foundation

// MARK: - FileEvent

struct FileEvent: Sendable {
    let path: String
    let flags: FileEventFlags
}

struct FileEventFlags: OptionSet, Sendable {
    let rawValue: FSEventStreamEventFlags

    init(rawValue: FSEventStreamEventFlags) { self.rawValue = rawValue }

    static let mustScanSubDirs  = Self(rawValue: 0x00010000)

    static let itemCreated      = Self(rawValue: 0x00000100)
    static let itemRemoved      = Self(rawValue: 0x00000200)
    static let itemRenamed      = Self(rawValue: 0x00000800)
    static let itemModified     = Self(rawValue: 0x00001000)
    static let itemInodeMetaMod = Self(rawValue: 0x00000400)
    static let itemFinderInfoMod = Self(rawValue: 0x00002000)
    static let itemChangeOwner  = Self(rawValue: 0x00004000)
    static let itemXattrMod     = Self(rawValue: 0x00008000)
    static let itemIsFile       = Self(rawValue: 0x00000010)
    static let itemIsDir        = Self(rawValue: 0x00000020)
    static let itemIsSymlink    = Self(rawValue: 0x00000040)
    static let itemIsHardLink   = Self(rawValue: 0x00000080)
    static let itemIsLastHardLink = Self(rawValue: 0x00004000)
}

// MARK: - FileWatcher

/// DispatchSource-based file watcher with AsyncStream support
/// Lock-free implementation, state managed by closures
final class FileWatcher {

    /// Create an AsyncStream for file events
    static func events(for path: String) -> AsyncStream<FileEvent> {
        AsyncStream { continuation in
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { return }

            let queue = DispatchQueue(label: "com.clashx.filewatcher", qos: .utility)
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename, .extend],
                queue: queue
            )

            source.setEventHandler {
                let flags = source.data
                var eventFlags = FileEventFlags()
                if flags.contains(.write) || flags.contains(.extend) {
                    eventFlags.insert(.itemModified)
                }
                if flags.contains(.delete) {
                    eventFlags.insert(.itemRemoved)
                }
                if flags.contains(.rename) {
                    eventFlags.insert(.itemRenamed)
                }
                let event = FileEvent(path: path, flags: eventFlags)
                continuation.yield(event)
            }

            source.setCancelHandler {
                close(fd)
            }

            source.resume()

            continuation.onTermination = { @Sendable _ in
                source.cancel()
            }
        }
    }
}
