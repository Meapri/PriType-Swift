import Foundation

/// Distribution channel for a PriType build or GitHub release.
public enum ReleaseChannel: String, Sendable, Codable {
    case stable
    case beta

    public var displayName: String {
        switch self {
        case .stable:
            return "Stable"
        case .beta:
            return "Beta"
        }
    }

    /// Detects the build channel from Info.plist metadata, falling back to
    /// version text so local beta builds can still identify themselves.
    public static func detect(plistValue: String?, version: String) -> ReleaseChannel {
        if let plistValue {
            let normalized = plistValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized == ReleaseChannel.beta.rawValue {
                return .beta
            }
            if normalized == ReleaseChannel.stable.rawValue {
                return .stable
            }
        }

        return detect(tagName: version, name: nil, prerelease: false)
    }

    /// Detects whether a GitHub release should be treated as stable or beta.
    ///
    /// GitHub's `prerelease` flag is authoritative. Tag/name markers are a
    /// secondary guard so a mistakenly unflagged `v3.0.0-beta.1` release does
    /// not appear in stable update checks.
    public static func detect(tagName: String, name: String?, prerelease: Bool) -> ReleaseChannel {
        if prerelease {
            return .beta
        }

        let text = [tagName, name].compactMap { $0 }.joined(separator: " ").lowercased()
        let betaMarkers = ["alpha", "beta", "rc", "preview", "nightly", "canary", "dev"]
        let tokens = text.split { !$0.isLetter && !$0.isNumber }.map(String.init)

        let hasBetaMarker = tokens.contains { token in
            betaMarkers.contains { marker in
                guard token.hasPrefix(marker) else { return false }
                if token == marker { return true }
                let suffix = token.dropFirst(marker.count)
                return suffix.first?.isNumber == true
            }
        }

        return hasBetaMarker ? .beta : .stable
    }
}
