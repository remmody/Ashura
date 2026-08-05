//
//  ReaderPagedViewModel.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import Foundation
import AshuraRunner

@MainActor
class ReaderPagedViewModel {
    let source: AshuraRunner.Source?
    let manga: AshuraRunner.Manga
    var chapter: AshuraRunner.Chapter?
    var pages: [Page] = []

    var preloadedChapter: AshuraRunner.Chapter?
    var preloadedPages: [Page] = []

    init(source: AshuraRunner.Source?, manga: AshuraRunner.Manga) {
        self.source = source
        self.manga = manga
    }

    func loadPages(chapter: AshuraRunner.Chapter) async {
        if preloadedChapter == chapter {
            pages = preloadedPages
            preloadedPages = []
            preloadedChapter = nil
        } else {
            if !pages.isEmpty {
                preloadedChapter = chapter
                preloadedPages = pages
            }
            self.chapter = chapter
            pages = await getPages(chapter: chapter)
        }
    }

    func preload(chapter: AshuraRunner.Chapter) async {
        guard preloadedChapter != chapter else { return }
        preloadedChapter = nil
        preloadedPages = await getPages(chapter: chapter)
        preloadedChapter = chapter
    }

    private func getPages(chapter: AshuraRunner.Chapter) async -> [Page] {
        let sourceId = source?.key ?? manga.sourceKey
        let identifier = ChapterIdentifier(
            sourceKey: sourceId,
            mangaKey: manga.key,
            chapterKey: chapter.key
        )
        let isDownloaded = DownloadManager.shared.isChapterDownloaded(chapter: identifier)
        if isDownloaded {
            return await DownloadManager.shared.getDownloadedPages(for: identifier)
                .map {
                    $0.toOld(sourceId: sourceId, chapterId: chapter.key)
                }
        } else {
            return (try? await source?
                .getPageList(
                    manga: manga,
                    chapter: chapter
                )
            )?
                .map {
                    $0.toOld(sourceId: sourceId, chapterId: chapter.key)
                } ?? []
        }
    }
}
