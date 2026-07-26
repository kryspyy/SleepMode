import CoreWLAN
import Foundation

final class WiFiService: WiFiControlling {
    private var interface: CWInterface? {
        CWWiFiClient.shared().interface()
    }

    var isPoweredOn: Bool {
        interface?.powerOn() ?? false
    }

    func setPower(_ poweredOn: Bool) throws {
        guard let interface else {
            throw SleepModeError.unavailable("No Wi-Fi interface is available.")
        }
        do {
            try interface.setPower(poweredOn)
        } catch {
            throw SleepModeError.operationFailed(
                "Could not turn Wi-Fi \(poweredOn ? "on" : "off"): \(error.localizedDescription)"
            )
        }

        guard interface.powerOn() == poweredOn else {
            throw SleepModeError.operationFailed("macOS did not confirm the Wi-Fi power change.")
        }
    }
}
