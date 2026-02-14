import AppKit
import Foundation

/// Checks GitHub Releases for a newer version on launch.
/// Compares semver from the latest release tag against the app's bundle version.
enum UpdateChecker {
    private static let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

    static func checkForUpdate() {
        let repo = Settings.shared.githubRepo
        guard !repo.isEmpty else { return }

        let urlString = "https://api.github.com/repos/\(repo)/releases/latest"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil else { return }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String
            else { return }

            let remoteVersion = tagName.trimmingCharacters(in: CharacterSet.letters.union(.whitespaces))

            if isNewer(remoteVersion, than: currentVersion) {
                DispatchQueue.main.async {
                    showUpdateAlert(version: remoteVersion, url: htmlURL)
                }
            } else {
                Log.info("Up to date (v\(currentVersion))")
            }
        }.resume()
    }

    private static func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }

    private static func showUpdateAlert(version: String, url: String) {
        let alert = NSAlert()
        alert.messageText = "Dict v\(version) Available"
        alert.informativeText = "A new version of Dict is available. You're running v\(currentVersion)."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .informational

        if alert.runModal() == .alertFirstButtonReturn {
            if let downloadURL = URL(string: url) {
                NSWorkspace.shared.open(downloadURL)
            }
        }
    }
}
