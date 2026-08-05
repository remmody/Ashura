//
//  PageTracker.swift
//  Aidoku
//
//  Created by Skitty on 10/6/25.
//

import AshuraRunner
import Foundation

/// A tracker that automatically tracks chapter read progress, syncing remote and local history.
protocol PageTracker: Tracker {
    /// Sets the read progress of a chapter.
    func setProgress(trackId: String, chapter: AshuraRunner.Chapter, progress: ChapterReadProgress) async throws

    /// Gets the read progress of multiple chapters.
    ///
    /// - Returns: A dictionary mapping chapter keys to their read progress.
    func getProgress(trackId: String, chapters: [AshuraRunner.Chapter]) async throws -> [String: ChapterReadProgress]
}

struct ChapterReadProgress: Codable {
    let completed: Bool
    let page: Int
    var date: Date?
}

struct PageTrackUpdate: Codable {
    let trackerId: String
    let trackId: String
    let chapter: AshuraRunner.Chapter
    let progress: ChapterReadProgress
    var failCount: Int = 0
}
