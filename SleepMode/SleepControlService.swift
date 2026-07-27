import Foundation

final class SleepControlService: SleepControlling {
    private let privilegedOperations: PrivilegedOperationsServing
    private let stateLock = NSLock()
    private var cachedState = false

    init(privilegedOperations: PrivilegedOperationsServing) {
        self.privilegedOperations = privilegedOperations
    }

    var isPreventingSleep: Bool {
        stateLock.withLock { cachedState }
    }

    func setPreventingSleep(
        _ enabled: Bool,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        privilegedOperations.setSleepDisabled(enabled) { [weak self] result in
            if case let .success(confirmedState) = result {
                self?.stateLock.withLock {
                    self?.cachedState = confirmedState
                }
            }
            completion(result)
        }
    }

    func restoreSafeDefaults() {
        stateLock.withLock {
            cachedState = false
        }
        privilegedOperations.restoreSafeDefaults()
    }
}
