import Foundation

@objc(SleepModePrivilegedHelperProtocol)
protocol SleepModePrivilegedHelperProtocol {
    func setSleepDisabled(
        _ disabled: Bool,
        withReply reply: @escaping (Bool, String?) -> Void
    )
}
