import Foundation

public enum L10n {
    public static var usesChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") ?? false
    }

    public static func t(_ zh: String, _ en: String) -> String {
        usesChinese ? zh : en
    }
}
