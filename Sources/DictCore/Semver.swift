import Foundation

/// Returns true if `remote` is a higher semver than `current`.
public func isNewerVersion(_ remote: String, than current: String) -> Bool {
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
