//
//  StreamQualityStore.swift
//  Aidoku
//
//  Ashura: remembers the user's preferred anime stream quality so they aren't asked
//  to pick a resolution before every episode.
//

import Foundation

/// Simple UserDefaults-backed store for the user's preferred anime stream quality
/// (e.g. "1080", "720", "480"), and helpers to resolve which stream page to play.
enum StreamQualityStore {
    private static let preferredQualityKey = "Player.preferredStreamQuality"

    /// The user's saved preferred stream quality, if any (e.g. "1080").
    static func preferredQuality() -> String? {
        UserDefaults.standard.string(forKey: preferredQualityKey)
    }

    /// Saves the user's preferred stream quality for future episodes.
    static func setPreferredQuality(_ quality: String) {
        UserDefaults.standard.set(quality, forKey: preferredQualityKey)
    }

    /// Parses the leading numeric component out of a quality label (e.g. "1080p" -> 1080).
    private static func qualityNumber(_ quality: String?) -> Int? {
        guard let quality else { return nil }
        let digits = quality.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }

    /// Picks the best stream page to play out of the given pages, honoring the user's
    /// saved quality preference when possible.
    ///
    /// - Exact match: if a page's quality matches the preferred quality exactly, use it.
    /// - Otherwise: pick the highest available quality that's <= the preferred quality;
    ///   if none is lower or equal, fall back to the highest available quality.
    /// - If no preference is saved, always pick the highest available quality.
    static func pick(from pages: [Page]) -> Page? {
        let streamPages = pages.filter(\.isStreamPage)
        guard !streamPages.isEmpty else { return nil }

        let sorted = streamPages.sorted {
            (qualityNumber($0.streamQuality) ?? 0) > (qualityNumber($1.streamQuality) ?? 0)
        }

        guard
            let preferred = preferredQuality(),
            let preferredNumber = qualityNumber(preferred)
        else {
            return sorted.first
        }

        if let exactMatch = sorted.first(where: { qualityNumber($0.streamQuality) == preferredNumber }) {
            return exactMatch
        }

        return sorted.first { (qualityNumber($0.streamQuality) ?? 0) <= preferredNumber } ?? sorted.first
    }
}
