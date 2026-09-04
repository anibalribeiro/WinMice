import Foundation

/// A value that can round-trip through `UserDefaults`.
public protocol PreferenceRepresentable: Sendable {
    /// Returns the stored value, or `nil` when nothing valid is stored yet.
    static func preferenceValue(in defaults: UserDefaults, forKey key: String) -> Self?
    func store(in defaults: UserDefaults, forKey key: String)
}

/// A `UserDefaults` key bundled with the value to use before the user picks one.
public struct Preference<Value: PreferenceRepresentable>: Sendable {
    public let key: String
    public let defaultValue: Value

    public init(_ key: String, default defaultValue: Value) {
        self.key = key
        self.defaultValue = defaultValue
    }
}

/// A `Preference` with its value type erased, so a group of them can be reflected over to
/// recover their keys without each call site naming the type.
protocol AnyPreference {
    var key: String { get }
}

extension Preference: AnyPreference {}

extension UserDefaults {
    subscript<Value: PreferenceRepresentable>(preference: Preference<Value>) -> Value {
        get { Value.preferenceValue(in: self, forKey: preference.key) ?? preference.defaultValue }
        set { newValue.store(in: self, forKey: preference.key) }
    }

    /// Whether the user has ever set this preference, as opposed to falling back to its default.
    func hasValue<Value: PreferenceRepresentable>(for preference: Preference<Value>) -> Bool {
        object(forKey: preference.key) != nil
    }
}

extension Bool: PreferenceRepresentable {
    public static func preferenceValue(in defaults: UserDefaults, forKey key: String) -> Bool? {
        defaults.object(forKey: key) as? Bool
    }

    public func store(in defaults: UserDefaults, forKey key: String) {
        defaults.set(self, forKey: key)
    }
}

extension Int: PreferenceRepresentable {
    public static func preferenceValue(in defaults: UserDefaults, forKey key: String) -> Int? {
        defaults.object(forKey: key) as? Int
    }

    public func store(in defaults: UserDefaults, forKey key: String) {
        defaults.set(self, forKey: key)
    }
}

extension PreferenceRepresentable where Self: RawRepresentable, RawValue == String {
    public static func preferenceValue(in defaults: UserDefaults, forKey key: String) -> Self? {
        defaults.string(forKey: key).flatMap(Self.init(rawValue:))
    }

    public func store(in defaults: UserDefaults, forKey key: String) {
        defaults.set(rawValue, forKey: key)
    }
}
