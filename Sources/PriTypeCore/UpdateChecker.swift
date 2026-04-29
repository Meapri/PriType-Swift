import Foundation

/// Checks for updates by querying the GitHub Releases API
///
/// `UpdateChecker` is the core engine that fetches the latest release info
/// from GitHub and compares it against the currently running version.
///
/// ## Usage
/// ```swift
/// if let update = await UpdateChecker.shared.checkForUpdates() {
///     print("New version available: \(update.version)")
/// }
/// ```
///
/// ## Throttling
/// `checkForUpdatesIfNeeded()` automatically skips the check if it was
/// performed less than 24 hours ago, preventing unnecessary API calls.
///
/// ## Thread Safety
/// All methods are `async` and safe to call from any context.
public final class UpdateChecker: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = UpdateChecker()
    
    // MARK: - Types
    
    /// Information about an available update
    public struct UpdateInfo: Sendable {
        /// The new version string (e.g. "2.1")
        public let version: String
        /// URL to the GitHub Releases page
        public let releasePageURL: URL
        /// Release notes / changelog body
        public let releaseNotes: String?
        /// Direct download URL for the PKG asset (if available)
        public let downloadURL: URL?
    }
    
    /// Result of an update check
    public enum CheckResult: Sendable {
        /// A newer version is available
        case updateAvailable(UpdateInfo)
        /// Already running the latest version
        case upToDate
        /// Check was skipped (throttled)
        case skipped
        /// An error occurred during the check
        case error(String)
    }
    
    // MARK: - GitHub API Response Models
    
    private struct GitHubRelease: Codable {
        let tagName: String
        let htmlUrl: String
        let name: String?
        let body: String?
        let prerelease: Bool
        let assets: [GitHubAsset]
        
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
            case name
            case body
            case prerelease
            case assets
        }
    }
    
    private struct GitHubAsset: Codable {
        let name: String
        let browserDownloadUrl: String
        
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
        }
    }
    
    // MARK: - Constants
    
    private let apiURL = "https://api.github.com/repos/Meapri/PriType-Swift/releases/latest"
    
    /// Minimum interval between automatic checks (24 hours)
    private let checkInterval: TimeInterval = 24 * 60 * 60
    
    // MARK: - Private Properties
    
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Public Methods
    
    /// Check for updates, respecting the throttle interval
    ///
    /// This method skips the API call if the last successful check was
    /// less than 24 hours ago. Use `checkForUpdates()` to force a check.
    ///
    /// - Returns: The result of the update check
    public func checkForUpdatesIfNeeded() async -> CheckResult {
        // Check if enough time has passed since last check
        if let lastCheck = ConfigurationManager.shared.lastUpdateCheck {
            let elapsed = Date().timeIntervalSince(lastCheck)
            if elapsed < checkInterval {
                DebugLogger.log("UpdateChecker: Skipping (last check \(Int(elapsed))s ago)")
                return .skipped
            }
        }
        
        return await checkForUpdates()
    }
    
    /// Force an immediate update check against GitHub Releases
    ///
    /// - Returns: The result of the update check
    public func checkForUpdates() async -> CheckResult {
        DebugLogger.log("UpdateChecker: Checking for updates...")
        
        guard let url = URL(string: apiURL) else {
            return .error("Invalid API URL")
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PriType/\(AboutInfo.version)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .error("Invalid response")
            }
            
            guard httpResponse.statusCode == 200 else {
                DebugLogger.log("UpdateChecker: HTTP \(httpResponse.statusCode)")
                return .error("HTTP \(httpResponse.statusCode)")
            }
            
            let decoder = JSONDecoder()
            let release = try decoder.decode(GitHubRelease.self, from: data)
            
            // Skip pre-releases
            if release.prerelease {
                DebugLogger.log("UpdateChecker: Latest release is pre-release, treating as up-to-date")
                ConfigurationManager.shared.lastUpdateCheck = Date()
                return .upToDate
            }
            
            // Compare versions
            let latestVersion = normalizeVersion(release.tagName)
            let currentVersion = normalizeVersion(AboutInfo.version)
            
            DebugLogger.log("UpdateChecker: current=\(currentVersion) latest=\(latestVersion)")
            
            // Record successful check time
            ConfigurationManager.shared.lastUpdateCheck = Date()
            
            if isNewer(latestVersion, than: currentVersion) {
                // Find PKG asset download URL
                let pkgAsset = release.assets.first { $0.name.hasSuffix(".pkg") }
                
                let updateInfo = UpdateInfo(
                    version: latestVersion,
                    releasePageURL: URL(string: release.htmlUrl) ?? url,
                    releaseNotes: release.body,
                    downloadURL: pkgAsset.flatMap { URL(string: $0.browserDownloadUrl) }
                )
                
                DebugLogger.log("UpdateChecker: Update available! \(latestVersion)")
                return .updateAvailable(updateInfo)
            } else {
                DebugLogger.log("UpdateChecker: Up to date")
                return .upToDate
            }
            
        } catch {
            DebugLogger.log("UpdateChecker: Error - \(error.localizedDescription)")
            return .error(error.localizedDescription)
        }
    }
    
    // MARK: - Version Comparison
    
    /// Normalize a version string by stripping leading "v" or "V"
    private func normalizeVersion(_ version: String) -> String {
        var v = version.trimmingCharacters(in: .whitespaces)
        if v.hasPrefix("v") || v.hasPrefix("V") {
            v = String(v.dropFirst())
        }
        return v
    }
    
    /// Check if `latest` is newer than `current` using numeric comparison
    ///
    /// Uses Foundation's `.numeric` comparison option which correctly handles
    /// dotted version strings (e.g. "2.1" > "2.0.0", "2.10" > "2.9")
    private func isNewer(_ latest: String, than current: String) -> Bool {
        return latest.compare(current, options: .numeric) == .orderedDescending
    }
}
