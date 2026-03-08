import Foundation
import SwiftUI

enum UserFacingText: Sendable, Equatable {
    case localized(LocalizedStringResource)
    case verbatim(String)

    var resolvedString: String {
        switch self {
        case .localized(let resource):
            return String(localized: resource)
        case .verbatim(let string):
            return string
        }
    }

    static func == (lhs: UserFacingText, rhs: UserFacingText) -> Bool {
        lhs.resolvedString == rhs.resolvedString
    }
}

extension Text {
    init(_ value: UserFacingText) {
        switch value {
        case .localized(let resource):
            self.init(resource)
        case .verbatim(let string):
            self.init(verbatim: string)
        }
    }
}