//
//  MediaKindPreferences.swift
//  Aidoku
//
//  Ashura: shared preferences for the dual manga/anime UX.
//

import Foundation

/// The kind of media a source, library item, or UI surface represents.
public enum AppMediaKind: String, Sendable, CaseIterable, Codable {
    case manga
    case anime
}

/// Centralized read/write access to the media-kind (manga vs anime) preferences
/// used across the library, browse, and history surfaces.
enum MediaKindPreferences {
    enum Keys {
        static let lastLibraryMediaKind = "ashura.library.mediaKind.last"
        static let defaultLibraryMediaKind = "ashura.library.mediaKind.default"
        static let browseMediaKind = "ashura.browse.mediaKind"
        static let historyMediaKind = "ashura.history.mediaKind"
    }

    private static func kind(forKey key: String, defaultValue: AppMediaKind) -> AppMediaKind {
        guard let raw = UserDefaults.standard.string(forKey: key) else {
            return defaultValue
        }
        return AppMediaKind(rawValue: raw) ?? defaultValue
    }

    private static func setKind(_ kind: AppMediaKind, forKey key: String) {
        UserDefaults.standard.set(kind.rawValue, forKey: key)
    }

    // MARK: Default library

    /// The media kind the Library tab should default to when no prior selection exists.
    static var defaultLibraryMediaKind: AppMediaKind {
        get { kind(forKey: Keys.defaultLibraryMediaKind, defaultValue: .manga) }
        set { setKind(newValue, forKey: Keys.defaultLibraryMediaKind) }
    }

    // MARK: Last selection

    /// The last media kind the user viewed in the Library tab.
    static var lastLibraryMediaKind: AppMediaKind {
        get { kind(forKey: Keys.lastLibraryMediaKind, defaultValue: defaultLibraryMediaKind) }
        set { setKind(newValue, forKey: Keys.lastLibraryMediaKind) }
    }

    // MARK: Browse filter

    static var browseMediaKind: AppMediaKind {
        get { kind(forKey: Keys.browseMediaKind, defaultValue: .manga) }
        set { setKind(newValue, forKey: Keys.browseMediaKind) }
    }

    // MARK: History filter

    static var historyMediaKind: AppMediaKind {
        get { kind(forKey: Keys.historyMediaKind, defaultValue: .manga) }
        set { setKind(newValue, forKey: Keys.historyMediaKind) }
    }
}
