import Foundation

struct ReleaseInfo: Decodable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
        let digest: String?
        let size: Int?
        init(name: String, browser_download_url: URL, digest: String? = nil, size: Int? = nil) {
            self.name = name; self.browser_download_url = browser_download_url; self.digest = digest; self.size = size
        }
        var sha256: String? {
            guard let digest, digest.hasPrefix("sha256:") else { return nil }
            let hex = String(digest.dropFirst(7)).lowercased()
            return hex.count == 64 && hex.allSatisfy { $0.isASCII && $0.isHexDigit } ? hex : nil
        }
    }
    let tag_name: String
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
    var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }
    static func validVersion(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } && Int($0) != nil }
    }
    func isNewer(than current: String) -> Bool {
        !draft && !prerelease && Self.validVersion(version) && Self.validVersion(current)
            && version.compare(current, options: .numeric) == .orderedDescending
    }
    var downloadAsset: Asset? {
        guard !draft, !prerelease, Self.validVersion(version) else { return nil }
        let filename = "FlowCat-\(version)-arm64.zip"
        return assets.first {
            $0.name == filename && $0.browser_download_url.scheme == "https"
                && $0.browser_download_url.host == "github.com"
                && $0.browser_download_url.user == nil && $0.browser_download_url.password == nil
                && $0.browser_download_url.query == nil && $0.browser_download_url.fragment == nil
                && ($0.browser_download_url.port == nil || $0.browser_download_url.port == 443)
                && $0.browser_download_url.path == "/tab16360/flowcat/releases/download/\(tag_name)/\(filename)"
        }
    }
    var downloadURL: URL? { downloadAsset?.browser_download_url }
    var installationAsset: Asset? {
        guard let asset = downloadAsset, asset.sha256 != nil, let size = asset.size, (1...UpdateArchive.maximumBytes).contains(size) else { return nil }
        return asset
    }
}
