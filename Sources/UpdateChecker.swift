import AppKit
import Foundation

/// Checks dict.tianxu.cloud/version for a newer version on launch.
/// If the remote version differs, prompts the user to open dict.studio to download.
enum UpdateChecker {
    private static let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    private static let versionURL = URL(string: "https://dict.tianxu.cloud/version")!
    private static let downloadURL = URL(string: "https://dict.studio")!

    static func checkForUpdate() {
        var request = URLRequest(url: versionURL)
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil,
                  let remoteVersion = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !remoteVersion.isEmpty
            else { return }

            if remoteVersion != currentVersion {
                Log.info("Update available: v\(remoteVersion) (current: v\(currentVersion))")
                DispatchQueue.main.async {
                    showUpdateAlert(version: remoteVersion)
                }
            } else {
                Log.info("Up to date (v\(currentVersion))")
            }
        }.resume()
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
}
