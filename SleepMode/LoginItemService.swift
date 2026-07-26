import Foundation
import ServiceManagement

final class LoginItemService: LoginItemControlling {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            throw SleepModeError.operationFailed(
                "Could not update Launch at Login: \(error.localizedDescription)"
            )
        }
    }
}
