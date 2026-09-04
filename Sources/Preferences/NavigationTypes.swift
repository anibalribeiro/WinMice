import SideButtons

public enum NavigationMethod: String, Hashable, CaseIterable, Identifiable, PreferenceRepresentable {
    case swipe
    case keyboard

    public var id: Self { self }
}

public enum NavigationDirection: Hashable, CaseIterable, Identifiable {
    case back
    case forward

    public var id: Self { self }

    public var opposite: NavigationDirection {
        switch self {
        case .back: .forward
        case .forward: .back
        }
    }

    public var title: String {
        switch self {
        case .back: "Back"
        case .forward: "Forward"
        }
    }

    public var defaultButton: Int {
        switch self {
        case .back: SideButtons.defaultBack
        case .forward: SideButtons.defaultForward
        }
    }
}
