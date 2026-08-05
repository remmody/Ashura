//
//  LocalSource.swift
//  Aidoku
//
//  Created by Skitty on 6/5/25.
//

import AshuraRunner
import Foundation

extension AshuraRunner.Source {
    static func local() -> AshuraRunner.Source {
        .init(
            url: nil,
            key: LocalSourceRunner.sourceKey,
            name: NSLocalizedString("LOCAL_FILES"),
            version: 1,
            languages: ["multi"],
            urls: [],
            contentRating: .safe,
            config: .init(
                languageSelectType: .single
            ),
            staticListings: [],
            staticFilters: [],
            staticSettings: [],
            runner: LocalSourceRunner()
        )
    }
}

final class LocalSourceRunner: AshuraRunner.Runner {
    static let sourceKey = "local"

    let features = AshuraRunner.SourceFeatures(
        providesListings: true,
        providesHome: false, // todo
        dynamicFilters: false,
        dynamicSettings: false,
        dynamicListings: false,
        processesPages: false,
        providesImageRequests: false,
        providesPageDescriptions: false,
        providesAlternateCovers: false,
        providesBaseUrl: false,
        handlesNotifications: false,
        handlesDeepLinks: false,
        handlesBasicLogin: false,
        handlesWebLogin: false
    )

    func getSearchMangaList(query: String?, page: Int, filters: [AshuraRunner.FilterValue]) async throws -> AshuraRunner.MangaPageResult {
        await LocalFileManager.shared.scanLocalFiles()
        let manga = await LocalFileDataManager.shared.fetchLocalSeries(query: query)
        return .init(entries: manga, hasNextPage: false)
    }

    func getMangaUpdate(manga: AshuraRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AshuraRunner.Manga {
        var manga = manga
        if needsDetails {}
        if needsChapters {
            manga.chapters = await LocalFileDataManager.shared.fetchChapters(mangaId: manga.key)
        }
        return manga
    }

    func getPageList(manga: AshuraRunner.Manga, chapter: AshuraRunner.Chapter) async throws -> [AshuraRunner.Page] {
        await LocalFileManager.shared.fetchPages(mangaId: manga.key, chapterId: chapter.key)
    }

    func getMangaList(listing: AshuraRunner.Listing, page: Int) async throws -> AshuraRunner.MangaPageResult {
        let manga = await LocalFileDataManager.shared.fetchLocalSeries()
        return .init(entries: manga, hasNextPage: false)
    }
}
