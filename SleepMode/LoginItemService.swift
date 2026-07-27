import Foundation
import ServiceManagement

final class LoginItemService: LoginItemControlling {
    private let queue = DispatchQueue(
        label: "local.sleepmode.login-item",
        qos: .userInitiated
    )

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(
        _ enabled: Bool,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        queue.async {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                completion(.success(SMAppService.mainApp.status == .enabled))
            } catch {
                completion(.failure(SleepModeError.operationFailed(
                    "Could not update Launch at Login: \(error.localizedDescription)"
                )))
            }
        }
    }
}
