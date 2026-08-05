//
//  ExternalSourceInfo.swift
//  Aidoku
//
//  Created by Skitty on 1/16/22.
//

import AshuraRunner
import Foundation

struct ExternalSourceInfo: Codable, Hashable {
    let id: String
    let name: String
    let version: Int
    let iconURL: String?
    let downloadURL: String?
    let languages: [String]?
    let contentRating: AshuraRunner.SourceContentRating?
    let altNames: [String]?
    let baseURL: String?
    let minAppVersion: String?
    let maxAppVersion: String?

    // Ashura: dual manga/anime catalog support
    /// "manga" or "anime"; defaults to manga when omitted.
    let mediaKind: String?
    /// "maintenance", "broken", or nil for a healthy source. Populated from an optional
    /// sibling `sources-status.json` merged in by `SourceManager.loadSourceLists`.
    var status: String?

    // deprecated
    let lang: String?
    let nsfw: Int?
    let file: String?
    let icon: String?

    var sourceUrl: URL?

    var fileURL: URL? {
        sourceUrl.flatMap { sourceUrl in
            if let downloadURL {
                URL(string: downloadURL, relativeTo: sourceUrl)
            } else if let file {
                URL(string: "sources/\(file)", relativeTo: sourceUrl)
            } else {
                nil
            }
        }
    }

    var resolvedContentRating: AshuraRunner.SourceContentRating {
        if let contentRating {
            contentRating
        } else if let nsfw, let rating = AshuraRunner.SourceContentRating(rawValue: nsfw) {
            rating
        } else {
            .safe
        }
    }

    /// Ashura: resolved media kind for this source, defaulting to manga when unset/unrecognized.
    var resolvedMediaKind: AppMediaKind {
        mediaKind.flatMap(AppMediaKind.init(rawValue:)) ?? .manga
    }

    /// Ashura: resolved catalog status badge, if the source is under maintenance or broken.
    var resolvedStatus: CatalogSourceStatus? {
        status.flatMap(CatalogSourceStatus.init(rawValue:))
    }
}

/// Ashura: entry format for the optional sibling `sources-status.json` file.
struct SourceStatusEntry: Codable, Hashable {
    let id: String
    let status: String?
}

/// Ashura: status badge shown for external catalog sources.
enum CatalogSourceStatus: String, Codable, Hashable {
    case maintenance
    case broken

    var localizedTitle: String {
        switch self {
            case .maintenance: NSLocalizedString("CATALOG_STATUS_MAINTENANCE", comment: "")
            case .broken: NSLocalizedString("CATALOG_STATUS_BROKEN", comment: "")
        }
    }
}

extension ExternalSourceInfo {
    func with(sourceUrl: URL) -> ExternalSourceInfo {
        var copy = self
        copy.sourceUrl = sourceUrl
        return copy
    }

    func toInfo() -> SourceInfo2 {
        let iconUrl: URL? = sourceUrl.flatMap { sourceUrl in
            if let iconURL {
                URL(string: iconURL, relativeTo: sourceUrl)
            } else if let icon {
                URL(string: "icons/\(icon)", relativeTo: sourceUrl)
            } else {
                nil
            }
        }
        return .init(
            sourceId: id,
            iconUrl: iconUrl,
            name: name,
            altNames: altNames ?? [],
            languages: languages ?? lang.flatMap { [$0] } ?? [],
            version: version,
            contentRating: resolvedContentRating,
            externalInfo: self
        )
    }
}
