import Foundation
import IOBluetooth
import ObjectiveC.runtime

final class BluetoothService: RadioControlling {
    // IOBluetoothHostController.setPowerState: is SPI. There is no public
    // replacement for toggling Bluetooth power.
    private typealias SetPowerStateFunction = @convention(c) (
        AnyObject,
        Selector,
        Int32
    ) -> Int32

    private let queue = DispatchQueue(
        label: "local.sleepmode.bluetooth",
        qos: .userInitiated
    )
    private let setPowerStateSelector = NSSelectorFromString("setPowerState:")

    func powerState(completion: @escaping (Result<Bool, Error>) -> Void) {
        queue.async {
            completion(Result { try self.readPowerState() })
        }
    }

    func setPower(
        _ poweredOn: Bool,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        queue.async {
            do {
                let controller = try self.controller()
                guard controller.responds(to: self.setPowerStateSelector) else {
                    throw SleepModeError.unavailable(
                        "Bluetooth power control is unavailable on this Mac."
                    )
                }

                let implementation = controller.method(
                    for: self.setPowerStateSelector
                )
                let setPowerState = unsafeBitCast(
                    implementation,
                    to: SetPowerStateFunction.self
                )
                let requestedState = poweredOn
                    ? kBluetoothHCIPowerStateON
                    : kBluetoothHCIPowerStateOFF
                let status = setPowerState(
                    controller,
                    self.setPowerStateSelector,
                    Int32(requestedState.rawValue)
                )
                guard status == 0 else {
                    throw SleepModeError.operationFailed(
                        "macOS could not change Bluetooth power (error \(status))."
                    )
                }

                let confirmedState = try self.waitForPowerState(poweredOn)
                completion(.success(confirmedState))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func controller() throws -> IOBluetoothHostController {
        guard let controller = IOBluetoothHostController.default() else {
            throw SleepModeError.unavailable(
                "No Bluetooth controller is available."
            )
        }
        return controller
    }

    private func readPowerState() throws -> Bool {
        let state = try controller().powerState
        if state == kBluetoothHCIPowerStateON {
            return true
        }
        if state == kBluetoothHCIPowerStateOFF {
            return false
        }
        throw SleepModeError.operationFailed(
            "Could not determine the Bluetooth power state."
        )
    }

    private func waitForPowerState(_ expected: Bool) throws -> Bool {
        for _ in 0..<40 {
            if try readPowerState() == expected {
                return expected
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw SleepModeError.operationFailed(
            "macOS did not confirm the Bluetooth power change."
        )
    }
}
