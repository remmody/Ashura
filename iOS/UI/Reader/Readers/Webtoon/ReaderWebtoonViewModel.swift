//
//  ReaderWebtoonViewModel.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 9/27/22.
//

import AshuraRunner
import Foundation

@MainActor
class ReaderWebtoonViewModel: ReaderPagedViewModel {
    func setPages(chapter: AshuraRunner.Chapter, pages: [Page]) {
        self.chapter = chapter
        self.pages = pages
        if preloadedChapter == chapter {
            preloadedPages = []
        }
    }
}
