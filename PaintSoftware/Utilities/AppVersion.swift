import Foundation

/// Names the build. `tools/stamp-build.sh` (a build phase) writes the commit, a "+" if the tree was
/// dirty, and the build time into the built Info.plist, so every build says what it is.
struct AppVersion {
    /// e.g. "Build 2891caad · Nov 20 22:31".
    static var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "PaintBuildLabel") as? String ?? "Build unknown"
    }

    /// e.g. "2891caad" or "2891caad+".
    static var commit: String {
        Bundle.main.object(forInfoDictionaryKey: "PaintBuildCommit") as? String ?? "unknown"
    }
}
