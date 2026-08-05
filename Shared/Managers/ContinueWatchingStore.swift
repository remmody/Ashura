//
//  ContinueWatchingStore.swift
//  Aidoku
//
//  Ashura: lightweight watch-progress store backing the "Continue Watching" shelf.
//

import Foundation

/// A single saved watch-progress entry for an anime stream.
struct ContinueWatchingEntry: Codable, Sendable, Equatable {
    let key: String
    var title: String?
    var position: Double
    var duration: Double
    var updatedAt: Date

    /// Fraction of the stream watched, from 0 to 1.
    var fractionWatched: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }
}

/// Simple UserDefaults-backed store tracking watch progress for anime streams,
/// used to populate the "Continue Watching" shelf.
///
/// Entries are keyed by an arbitrary identifier (e.g. `sourceId|mangaId|chapterId`)
/// and stored under `ashura.watchProgress.<key>`.
enum ContinueWatchingStore {
    private static let defaultsKeyPrefix = "ashura.watchProgress."
    private static let indexKey = "ashura.watchProgress.index"

    static func makeKey(sourceId: String, mangaId: String, chapterId: String) -> String {
        "\(sourceId)|\(mangaId)|\(chapterId)"
    }

    private static func storageKey(for key: String) -> String {
        "\(defaultsKeyPrefix)\(key)"
    }

    /// Saves (or updates) the watch progress for a given key.
    static func save(key: String, title: String? = nil, position: Double, duration: Double) {
        let entry = ContinueWatchingEntry(
            key: key,
            title: title,
            position: position,
            duration: duration,
            updatedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(entry) else { return }
        UserDefaults.standard.set(data, forKey: storageKey(for: key))

        var index = Set(UserDefaults.standard.stringArray(forKey: indexKey) ?? [])
        index.insert(key)
        UserDefaults.standard.set(Array(index), forKey: indexKey)
    }

    /// Fetches the saved progress for a given key, if any.
    static func progress(key: String) -> ContinueWatchingEntry? {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey(for: key)),
            let entry = try? JSONDecoder().decode(ContinueWatchingEntry.self, from: data)
        else {
            return nil
        }
        return entry
    }

    /// Returns all saved watch-progress entries, most recently updated first.
    static func allEntries() -> [ContinueWatchingEntry] {
        let keys = UserDefaults.standard.stringArray(forKey: indexKey) ?? []
        let entries: [ContinueWatchingEntry] = keys.compactMap { key in
            guard
                let data = UserDefaults.standard.data(forKey: storageKey(for: key)),
                let entry = try? JSONDecoder().decode(ContinueWatchingEntry.self, from: data)
            else {
                return nil
            }
            return entry
        }
        return entries.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Removes a saved entry, e.g. once a stream has been fully watched.
    static func remove(key: String) {
        UserDefaults.standard.removeObject(forKey: storageKey(for: key))
        var index = Set(UserDefaults.standard.stringArray(forKey: indexKey) ?? [])
        index.remove(key)
        UserDefaults.standard.set(Array(index), forKey: indexKey)
    }
}
