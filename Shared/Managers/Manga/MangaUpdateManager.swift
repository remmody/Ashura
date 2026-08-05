//
//  MangaUpdateManager.swift
//  Aidoku
//
//  Created by axiel7 on 17/03/2024.
//

import AshuraRunner
import CoreData

struct MangaUpdateManager {
    static let shared = MangaUpdateManager()
}

extension MangaUpdateManager {
    func viewAllUpdates(of manga: AshuraRunner.Manga) async {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            let updates = CoreDataManager.shared.setMangaUpdatesViewed(
                sourceId: manga.sourceKey,
                mangaId: manga.key,
                context: context
            )
            if !updates.isEmpty {
                NotificationCenter.default.post(name: NSNotification.Name("mangaUpdatesViewed"), object: updates.map { $0.toItem() })
            }
        }
    }
}
