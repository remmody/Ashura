//
//  Download.swift
//  Aidoku
//
//  Created by Skitty on 5/14/22.
//

import AshuraRunner
import Foundation

enum DownloadStatus: Int, Codable {
    case none = 0
    case queued
    case downloading
    case paused
    case cancelled
    case finished
    case failed
}

struct Download: Equatable, Sendable, Codable {
    var mangaIdentifier: MangaIdentifier { chapterIdentifier.mangaIdentifier }
    let chapterIdentifier: ChapterIdentifier

    var status: DownloadStatus = .queued

    var progress: Int = 0
    var total: Int = 0

    var manga: AshuraRunner.Manga
    var chapter: AshuraRunner.Chapter

    static func == (lhs: Download, rhs: Download) -> Bool {
        lhs.chapterIdentifier == rhs.chapterIdentifier
    }

    static func from(
        manga: AshuraRunner.Manga,
        chapter: AshuraRunner.Chapter,
        status: DownloadStatus = .queued
    ) -> Download {
        Download(
            chapterIdentifier: .init(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapter.key),
            status: status,
            manga: manga,
            chapter: chapter
        )
    }
}

extension Download: Identifiable {
    var id: ChapterIdentifier { chapterIdentifier }
}
