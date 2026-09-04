import CoreServices
import Foundation

public struct DirectoryEventFlags: OptionSet, Equatable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let created = DirectoryEventFlags(rawValue: 1 << 0)
    public static let renamed = DirectoryEventFlags(rawValue: 1 << 1)
    public static let contentModified = DirectoryEventFlags(rawValue: 1 << 2)
    public static let metadataModified = DirectoryEventFlags(rawValue: 1 << 3)
    public static let removed = DirectoryEventFlags(rawValue: 1 << 4)
    public static let directory = DirectoryEventFlags(rawValue: 1 << 5)
    public static let ownEvent = DirectoryEventFlags(rawValue: 1 << 6)
    public static let mustRescan = DirectoryEventFlags(rawValue: 1 << 7)
    public static let rootChanged = DirectoryEventFlags(rawValue: 1 << 8)

    public var isCandidateEvent: Bool {
        !intersection([.created, .renamed, .contentModified, .metadataModified]).isEmpty
    }
}

public struct DirectoryEvent: Equatable {
    public let url: URL
    public let flags: DirectoryEventFlags

    public init(url: URL, flags: DirectoryEventFlags) {
        self.url = url
        self.flags = flags
    }
}

public protocol DirectoryEventWatching: AnyObject {
    func start(
        watching directory: URL,
        handler: @escaping ([DirectoryEvent]) -> Void
    ) throws
    func stop()
}

public enum DirectoryEventWatcherError: Error, Equatable, LocalizedError {
    case alreadyStarted
    case couldNotCreateStream
    case couldNotStartStream

    public var errorDescription: String? {
        switch self {
        case .alreadyStarted:
            return "The folder watcher is already running."
        case .couldNotCreateStream:
            return "macOS could not create a folder event stream."
        case .couldNotStartStream:
            return "macOS could not start the folder event stream."
        }
    }
}

public final class FSEventDirectoryWatcher: DirectoryEventWatching {
    public static let latency: CFTimeInterval = 0.10

    private let callbackQueue: DispatchQueue
    private let handlerLock = NSLock()
    private var stream: FSEventStreamRef?
    private var handler: (([DirectoryEvent]) -> Void)?

    public init(
        callbackQueue: DispatchQueue = DispatchQueue(
            label: "dev.j-256.timestamponly.fsevents"
        )
    ) {
        self.callbackQueue = callbackQueue
    }

    deinit {
        stop()
    }

    public func start(
        watching directory: URL,
        handler: @escaping ([DirectoryEvent]) -> Void
    ) throws {
        guard stream == nil else {
            throw DirectoryEventWatcherError.alreadyStarted
        }

        setHandler(handler)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let createFlags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagIgnoreSelf
                | kFSEventStreamCreateFlagMarkSelf
                | kFSEventStreamCreateFlagUseCFTypes
        )

        guard
            let newStream = FSEventStreamCreate(
                kCFAllocatorDefault,
                timestampOnlyFSEventCallback,
                &context,
                [directory.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                Self.latency,
                createFlags
            )
        else {
            setHandler(nil)
            throw DirectoryEventWatcherError.couldNotCreateStream
        }

        FSEventStreamSetDispatchQueue(newStream, callbackQueue)
        guard FSEventStreamStart(newStream) else {
            FSEventStreamInvalidate(newStream)
            FSEventStreamRelease(newStream)
            setHandler(nil)
            throw DirectoryEventWatcherError.couldNotStartStream
        }
        stream = newStream
    }

    public func stop() {
        guard let stream else {
            return
        }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        setHandler(nil)
    }

    fileprivate func receive(
        count: Int,
        eventPaths: UnsafeMutableRawPointer,
        eventFlags: UnsafePointer<FSEventStreamEventFlags>
    ) {
        let paths = unsafeBitCast(eventPaths, to: NSArray.self)
        var events: [DirectoryEvent] = []
        events.reserveCapacity(count)

        for index in 0..<count {
            guard let path = paths[index] as? String else {
                continue
            }
            events.append(
                DirectoryEvent(
                    url: URL(fileURLWithPath: path),
                    flags: Self.translate(eventFlags[index])
                ))
        }

        if !events.isEmpty {
            currentHandler()?(events)
        }
    }

    private func setHandler(_ handler: (([DirectoryEvent]) -> Void)?) {
        handlerLock.lock()
        self.handler = handler
        handlerLock.unlock()
    }

    private func currentHandler() -> (([DirectoryEvent]) -> Void)? {
        handlerLock.lock()
        let handler = handler
        handlerLock.unlock()
        return handler
    }

    private static func translate(
        _ flags: FSEventStreamEventFlags
    ) -> DirectoryEventFlags {
        var translated: DirectoryEventFlags = []

        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) != 0 {
            translated.insert(.created)
        }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed) != 0 {
            translated.insert(.renamed)
        }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified) != 0 {
            translated.insert(.contentModified)
        }
        if flags
            & FSEventStreamEventFlags(
                kFSEventStreamEventFlagItemInodeMetaMod
                    | kFSEventStreamEventFlagItemFinderInfoMod
                    | kFSEventStreamEventFlagItemChangeOwner
                    | kFSEventStreamEventFlagItemXattrMod
            ) != 0
        {
            translated.insert(.metadataModified)
        }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) != 0 {
            translated.insert(.removed)
        }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0 {
            translated.insert(.directory)
        }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagOwnEvent) != 0 {
            translated.insert(.ownEvent)
        }
        if flags
            & FSEventStreamEventFlags(
                kFSEventStreamEventFlagMustScanSubDirs
                    | kFSEventStreamEventFlagUserDropped
                    | kFSEventStreamEventFlagKernelDropped
                    | kFSEventStreamEventFlagEventIdsWrapped
            ) != 0
        {
            translated.insert(.mustRescan)
        }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 {
            translated.insert([.mustRescan, .rootChanged])
        }

        return translated
    }
}

private let timestampOnlyFSEventCallback: FSEventStreamCallback = {
    _, callbackInfo, eventCount, eventPaths, eventFlags, _ in
    guard let callbackInfo else {
        return
    }
    let watcher = Unmanaged<FSEventDirectoryWatcher>
        .fromOpaque(callbackInfo)
        .takeUnretainedValue()
    watcher.receive(
        count: eventCount,
        eventPaths: eventPaths,
        eventFlags: eventFlags
    )
}
