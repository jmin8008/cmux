import Foundation

extension MainWindowFocusController {
    enum EffectiveFocusOwner {
        case mainPanel
        case rightSidebar
        case unknown
    }

    enum RightSidebarFocusTarget: Equatable {
        case host
        case outline
        case searchField
        case firstItem
    }

    struct RightSidebarFocusRequest: Equatable {
        let id: UInt64
        let mode: RightSidebarMode
        let target: RightSidebarFocusTarget
    }

    enum RightSidebarFocusState: Equatable {
        case inactive
        case requested(RightSidebarFocusRequest)
        case focused(mode: RightSidebarMode, target: RightSidebarFocusTarget)

        var mode: RightSidebarMode? {
            switch self {
            case .inactive:
                return nil
            case .requested(let request):
                return request.mode
            case .focused(let mode, _):
                return mode
            }
        }

        var request: RightSidebarFocusRequest? {
            if case .requested(let request) = self {
                return request
            }
            return nil
        }
    }

}
