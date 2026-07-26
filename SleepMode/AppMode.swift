import Foundation

enum AppMode: String, CaseIterable, Codable, Identifiable {
    case stayAwake
    case normal

    var id: Self { self }

    var title: String {
        switch self {
        case .stayAwake: "Stay Awake"
        case .normal: "Normal"
        }
    }

    var symbolName: String {
        switch self {
        case .stayAwake: "sun.max.fill"
        case .normal: "moon.zzz.fill"
        }
    }
}
