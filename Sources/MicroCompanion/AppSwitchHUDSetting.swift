import Foundation

struct AppSwitchHUDSetting {
    enum Trigger { case appSwitch, manual, silent }

    private static let key = "showAppSwitchHUD"
    let preferences: UserDefaults

    var isEnabled: Bool {
        get { preferences.object(forKey: Self.key) as? Bool ?? true }
        nonmutating set { preferences.set(newValue, forKey: Self.key) }
    }

    func allows(_ trigger: Trigger) -> Bool {
        switch trigger {
        case .appSwitch: return isEnabled
        case .manual: return true
        case .silent: return false
        }
    }
}
