import AppKit
import Foundation

/// Checks dict.tianxu.cloud/version for a newer version.
/// If the remote version differs, prompts the user to download.
enum UpdateChecker {
    private static let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    private static let versionURL = URL(string: "https://dict.tianxu.cloud/version")!
    private static let downloadURL = URL(string: "https://dict.studio/Dict.dmg")!

    /// - Parameter silent: When true, only shows alert if update is available (used on launch).
    ///                     When false, always shows feedback (used for manual check).
    static func checkForUpdate(silent: Bool = false) {
        var request = URLRequest(url: versionURL)
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    Log.info("Update check failed: \(error.localizedDescription)")
                    if !silent {
                        showErrorAlert()
                    }
                    return
                }

                guard let data = data,
                      let remoteVersion = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !remoteVersion.isEmpty
                else {
                    if !silent { showErrorAlert() }
                    return
                }

                if isNewerVersion(remoteVersion, than: currentVersion) {
                    Log.info("Update available: v\(remoteVersion) (current: v\(currentVersion))")
                    showUpdateAlert(version: remoteVersion)
                } else {
                    Log.info("Up to date (v\(currentVersion))")
                    if !silent {
                        showUpToDateAlert()
                    }
                }
            }
        }.resume()
    }

    /// Returns true if `remote` is a higher semver than `current`.
    private static func isNewerVersion(_ remote: String, than current: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, c.count) {
            let rv = i < r.count ? r[i] : 0
            let cv = i < c.count ? c[i] : 0
            if rv > cv { return true }
            if rv < cv { return false }
        }
        return false
    }

    private static func showUpdateAlert(version: String) {
        let alert = NSAlert()
        alert.messageText = "Dict v\(version) Available"
        alert.informativeText = "A new version of Dict is available. You're running v\(currentVersion)."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .informational

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(downloadURL)
        }
    }

    private static func showUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "Dict v\(currentVersion) is the latest version."
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .informational
        alert.runModal()
    }

    private static func showErrorAlert() {
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = "Could not connect to the update server. Please try again later."
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .warning
        alert.runModal()
    }
}
