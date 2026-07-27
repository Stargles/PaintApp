import Foundation

/// Tracks the current app version for debugging purposes. Reads the bundle's own version info
/// (Xcode's MARKETING_VERSION/CURRENT_PROJECT_VERSION build settings) rather than a hardcoded git
/// hash — a manually-updated constant would immediately drift out of sync with HEAD.
struct AppVersion {
    /// A human-readable version string, e.g. "v1.0 (1)".
    static var versionString: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "v\(shortVersion) (\(build))"
    }
}
