import Foundation
import Postbox
import SwiftSignalKit

public struct CallListSettings: PreferencesEntry, Equatable {
    public let showTab: Bool
    
    public static var defaultSettings: CallListSettings {
        return CallListSettings(showTab: true)
    }
    
    public init(showTab: Bool) {
        self.showTab = showTab
    }
    
    public init(decoder: PostboxDecoder) {
        self.showTab = decoder.decodeInt32ForKey("showTab", orElse: 0) != 0
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.showTab ? 1 : 0, forKey: "showTab")
    }
    
    public func isEqual(to: PreferencesEntry) -> Bool {
        if let to = to as? CallListSettings {
            return self == to
        } else {
            return false
        }
    }
    
    public static func ==(lhs: CallListSettings, rhs: CallListSettings) -> Bool {
        return lhs.showTab == rhs.showTab
    }
    
    func withUpdatedShowTab(_ showTab: Bool) -> CallListSettings {
        return CallListSettings(showTab: showTab)
    }
}

func updateCallListSettingsInteractively(postbox: Postbox, _ f: @escaping (CallListSettings) -> CallListSettings) -> Signal<Void, NoError> {
    return postbox.modify { modifier -> Void in
        modifier.updatePreferencesEntry(key: ApplicationSpecificPreferencesKeys.callListSettings, { entry in
            let currentSettings: CallListSettings
            if let entry = entry as? CallListSettings {
                currentSettings = entry
            } else {
                currentSettings = CallListSettings.defaultSettings
            }
            return f(currentSettings)
        })
    }
}
