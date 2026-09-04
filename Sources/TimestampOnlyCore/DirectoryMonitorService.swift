import Foundation

public enum DirectoryMonitorState: Equatable {
    case stopped
    case running
    case paused
    case error
}

public struct DirectoryMonitorUpdate: Equatable {
    public let state: DirectoryMonitorState
    public let directory: URL?
    public let outcomes: [DirectoryRenameEngineOutcome]
    public let errorMessage: String?

    public init(
        state: DirectoryMonitorState,
        directory: URL?,
        outcomes: [DirectoryRenameEngineOutcome] = [],
        errorMessage: String? = nil
    ) {
        self.state = state
        self.directory = directory
        self.outcomes = outcomes
        self.errorMessage = errorMessage
    }
}

public final class DirectoryMonitorService {
    public static let processingInterval: TimeInterval = 0.10

    public var updateHandler: ((DirectoryMonitorUpdate) -> Void)?

    private let queue: DispatchQueue
    private let callbackQueue: DispatchQueue
    private let watcherFactory: () -> DirectoryEventWatching
    private let engineFactory: (URL) -> DirectoryRenameEngine
    private var watcher: DirectoryEventWatching?
    private var engine: DirectoryRenameEngine?
    private var timer: DispatchSourceTimer?
    private var settings = RenameSettings.default
    private var directory: URL?
    private var state = DirectoryMonitorState.stopped
    private var generation = 0

    public init(
        queue: DispatchQueue = DispatchQueue(
            label: "dev.j-256.timestamponly.monitor"
        ),
        callbackQueue: DispatchQueue = .main,
        watcherFactory: @escaping () -> DirectoryEventWatching = {
            FSEventDirectoryWatcher()
        },
        engineFactory: @escaping (URL) -> DirectoryRenameEngine = {
            DirectoryRenameEngine(directory: $0)
        }
    ) {
        self.queue = queue
        self.callbackQueue = callbackQueue
        self.watcherFactory = watcherFactory
        self.engineFactory = engineFactory
    }

    deinit {
        watcher?.stop()
        timer?.cancel()
    }

    public func start(directory: URL, settings: RenameSettings) throws {
        var caughtError: Error?
        queue.sync {
            do {
                try startLocked(directory: directory, settings: settings)
            } catch {
                caughtError = error
            }
        }
        if let caughtError {
            throw caughtError
        }
    }

    public func update(settings: RenameSettings) {
        queue.async { [weak self] in
            self?.settings = settings
        }
    }

    public func pause() {
        queue.sync {
            guard state == .running || state == .error else {
                return
            }
            stopRuntimeLocked()
            state = .paused
            emitLocked(DirectoryMonitorUpdate(state: .paused, directory: directory))
        }
    }

    public func resume() throws {
        var caughtError: Error?
        queue.sync {
            guard let directory else {
                caughtError = DirectoryEventWatcherError.couldNotCreateStream
                return
            }
            do {
                try startLocked(directory: directory, settings: settings)
            } catch {
                caughtError = error
            }
        }
        if let caughtError {
            throw caughtError
        }
    }

    public func stop() {
        queue.sync {
            stopRuntimeLocked()
            directory = nil
            state = .stopped
            emitLocked(DirectoryMonitorUpdate(state: .stopped, directory: nil))
        }
    }

    private func startLocked(directory: URL, settings: RenameSettings) throws {
        stopRuntimeLocked()

        let standardizedDirectory = directory.standardizedFileURL
        let nextGeneration = generation + 1
        let nextWatcher = watcherFactory()
        var nextEngine = engineFactory(standardizedDirectory)
        let monitoringStartDate = Date()

        do {
            try nextWatcher.start(watching: standardizedDirectory) { [weak self] events in
                self?.queue.async { [weak self] in
                    self?.receiveLocked(events, generation: nextGeneration)
                }
            }
            try nextEngine.establishBaseline(startedAt: monitoringStartDate)
        } catch {
            nextWatcher.stop()
            self.directory = standardizedDirectory
            state = .error
            emitLocked(
                DirectoryMonitorUpdate(
                    state: .error,
                    directory: standardizedDirectory,
                    errorMessage: error.localizedDescription
                ))
            throw error
        }

        generation = nextGeneration
        watcher = nextWatcher
        engine = nextEngine
        self.settings = settings
        self.directory = standardizedDirectory
        state = .running
        startTimerLocked(generation: nextGeneration)
        emitLocked(
            DirectoryMonitorUpdate(
                state: .running,
                directory: standardizedDirectory
            ))
    }

    private func receiveLocked(_ events: [DirectoryEvent], generation: Int) {
        guard generation == self.generation,
            state == .running,
            var engine
        else {
            return
        }

        do {
            try engine.receive(events, at: Date())
            self.engine = engine
        } catch {
            transitionToErrorLocked(error)
        }
    }

    private func processLocked(generation: Int) {
        guard generation == self.generation,
            state == .running,
            var engine
        else {
            return
        }

        let outcomes = engine.processDueCandidates(settings: settings, at: Date())
        self.engine = engine
        if !outcomes.isEmpty {
            emitLocked(
                DirectoryMonitorUpdate(
                    state: .running,
                    directory: directory,
                    outcomes: outcomes
                ))
        }
    }

    private func startTimerLocked(generation: Int) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + Self.processingInterval,
            repeating: Self.processingInterval,
            leeway: .milliseconds(25)
        )
        timer.setEventHandler { [weak self] in
            self?.processLocked(generation: generation)
        }
        timer.resume()
        self.timer = timer
    }

    private func transitionToErrorLocked(_ error: Error) {
        stopRuntimeLocked()
        state = .error
        emitLocked(
            DirectoryMonitorUpdate(
                state: .error,
                directory: directory,
                errorMessage: error.localizedDescription
            ))
    }

    private func stopRuntimeLocked() {
        generation += 1
        watcher?.stop()
        watcher = nil
        timer?.cancel()
        timer = nil
        engine = nil
    }

    private func emitLocked(_ update: DirectoryMonitorUpdate) {
        callbackQueue.async { [weak self] in
            self?.updateHandler?(update)
        }
    }
}
