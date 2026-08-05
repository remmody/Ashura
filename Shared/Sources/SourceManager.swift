//
//  SourceManager.swift
//  Aidoku
//
//  Created by Skitty on 1/10/22.
//

import AshuraRunner
import Foundation
import ZIPFoundation

#if canImport(UIKit)
import UIKit
#endif

class SourceManager {
    static let shared = SourceManager()

    static let directory = FileManager.default.applicationSupportDirectory.appendingPathComponent("Sources", isDirectory: true)
    static let oldDirectory = FileManager.default.documentDirectory.appendingPathComponent("Sources", isDirectory: true) // used for migration

    var sources: [AshuraRunner.Source] = []
    var sourceLists: [SourceList] = []
    var sourceListURLs: [URL]
    var sourceListLanguages: Set<String> = []

    // Ashura: separate anime source list storage, parallel to the manga lists above.
    var animeSourceLists: [SourceList] = []
    var animeSourceListURLs: [URL]
    var animeSourceListLanguages: Set<String> = []

    private var loadSourcesTask: Task<(), Never>?
    private var loadSourceListsTask: Task<(), Never>?
    private var loadAnimeSourceListsTask: Task<(), Never>?

    static let languageCodes = [
        "multi", "en", "ca", "de", "es", "fr", "id", "it", "pl", "pt-br", "vi", "tr", "ru", "ar", "zh", "zh-hans", "ja", "ko"
    ]

    var sourceListsStrings: [String] {
        sourceListURLs.map { $0.absoluteString }
    }

    var animeSourceListsStrings: [String] {
        animeSourceListURLs.map { $0.absoluteString }
    }

    /// Ashura: source lists for the currently selected browse media kind.
    var currentMediaKindSourceLists: [SourceList] {
        MediaKindPreferences.browseMediaKind == .anime ? animeSourceLists : sourceLists
    }

    var localSourceInstalled: Bool {
        sources.contains(where: { $0.id == LocalSourceRunner.sourceKey })
    }

    init() {
        sourceListURLs = (UserDefaults.standard.array(forKey: "Browse.sourceLists") as? [String] ?? [])
            .compactMap { URL(string: $0) }
        animeSourceListURLs = (UserDefaults.standard.array(forKey: "ashura.sourceLists.anime") as? [String] ?? [])
            .compactMap { URL(string: $0) }

        loadSourcesTask = Task {
            await reloadSources()
        }

        Task {
            await loadSourceLists(reload: true)
        }
        Task {
            await loadAnimeSourceLists(reload: true)
        }
    }

    func reloadSources() async {
        // load installed sources
        sources = await getInstalledSources()
        sortSources()
        await MainActor.run {
            for source in sources {
                NotificationCenter.default.post(name: .sourceLoaded, object: source.key)
            }
            NotificationCenter.default.post(name: .updateSourceList, object: nil)
        }

        // load source filters
        await withTaskGroup(of: Void.self) { group in
            for source in sources {
                if let legacySource = source.legacySource {
                    group.addTask {
                        _ = try? await legacySource.getFilters()
                    }
                }
            }
        }
        await MainActor.run {
            NotificationCenter.default.post(name: .loadedSourceFilters, object: nil)
        }
    }

    func waitForSourcesLoad() async {
        await loadSourcesTask?.value
    }

    func loadSourceLists(reload: Bool = false) async {
        if let loadSourceListsTask {
            await loadSourceListsTask.value
            self.loadSourceListsTask = nil
        }
        if reload {
            loadSourceListsTask = Task {
                sourceLists = await withTaskGroup(of: SourceList?.self) { group in
                    for url in sourceListURLs {
                        // load sources from list
                        group.addTask {
                            await self.loadSourceList(url: url)
                        }
                    }
                    var results: [SourceList] = []
                    for await result in group {
                        guard let result else { continue }
                        results.append(result)
                    }
                    return results
                }
                loadSourceListLanguages()
                NotificationCenter.default.post(name: .updateSourceLists, object: nil)
            }
            await loadSourceListsTask?.value
        }
    }

    /// Ashura: anime equivalent of `loadSourceLists`.
    func loadAnimeSourceLists(reload: Bool = false) async {
        if let loadAnimeSourceListsTask {
            await loadAnimeSourceListsTask.value
            self.loadAnimeSourceListsTask = nil
        }
        if reload {
            loadAnimeSourceListsTask = Task {
                animeSourceLists = await withTaskGroup(of: SourceList?.self) { group in
                    for url in animeSourceListURLs {
                        group.addTask {
                            await self.loadSourceList(url: url)
                        }
                    }
                    var results: [SourceList] = []
                    for await result in group {
                        guard let result else { continue }
                        results.append(result)
                    }
                    return results
                }
                loadAnimeSourceListLanguages()
                NotificationCenter.default.post(name: .updateSourceLists, object: nil)
            }
            await loadAnimeSourceListsTask?.value
        }
    }

    func getInstalledSources() async -> [AshuraRunner.Source] {
        let objects: [SourceObjectData] = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getSources(context: context).map { $0.toData() }
        }
        var sources: [AshuraRunner.Source] = []
        for dbSource in objects {
            if let source = await dbSource.toNewSource() {
                if sources.contains(where: { $0.id == source.id }) {
                    // remove duplicate coredata sources
                    CoreDataManager.shared.remove(dbSource.objectID)
                } else {
                    sources.append(source)
                }
            } else {
                LogManager.logger.error("Failed to load source \(dbSource.id)")
            }
        }
        return sources
    }
}

// MARK: - Source Management
extension SourceManager {
    func source(for id: String) -> AshuraRunner.Source? {
        sources.first { $0.id == id }
    }

    func hasSourceInstalled(id: String) -> Bool {
        sources.contains { $0.id == id }
    }

    func importSource(from url: URL) async -> AshuraRunner.Source? {
        Self.directory.createDirectory()

        // download and unzip source aix
        guard let temporaryDirectory = FileManager.default.temporaryDirectory else { return nil }
        var secured = false
        var fileUrl = url
        if fileUrl.scheme != "file" {
            do {
                let location = try await URLSession.shared.download(for: URLRequest.from(url))
                fileUrl = location
            } catch {
                LogManager.logger.error("Failed to download source from \(url)")
                return nil
            }
        } else {
            secured = url.startAccessingSecurityScopedResource()
        }
        defer {
            if secured {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            try FileManager.default.unzipItem(at: fileUrl, to: temporaryDirectory)
        } catch {
            LogManager.logger.error("Failed to unarchive source package: \(error)")
            return nil
        }

        // try initializing the source
        let payload = temporaryDirectory.appendingPathComponent("Payload")
        var newSource: AshuraRunner.Source?
        let legacySource: Source?

        do {
            newSource = try await AshuraRunner.Source(url: payload)
            legacySource = nil
        } catch {
            newSource = nil
            legacySource = try? Source(from: payload)

            if legacySource == nil {
                LogManager.logger.error("Failed to load source: \(error)")
                return nil
            }
        }

        let id: String
        if let newSource {
            id = newSource.id
        } else if let legacySource {
            id = legacySource.id
        } else {
            return nil
        }

        // ensure id is valid
        guard isValidSourceKey(id) else {
            LogManager.logger.error("Invalid source key: \(id)")
            return nil
        }

        // move to final location
        let destination = Self.directory.appendingPathComponent(id)
        if destination.exists {
            try? FileManager.default.removeItem(at: destination)
        }
        do {
            try FileManager.default.moveItem(at: payload, to: destination)
        } catch {
            LogManager.logger.error("Failed to unarchive source package: \(error)")
            return nil
        }
        try? FileManager.default.removeItem(at: temporaryDirectory)

        // update initialized location
        if newSource != nil {
            newSource = try? await AshuraRunner.Source(id: id, url: destination)
        } else if let legacySource {
            legacySource.url = destination
        }

        // remove old source version (on update)
        let installedSource = sources
            .firstIndex { $0.id == id }
            .flatMap { sources.remove(at: $0) }
        if installedSource != nil {
            await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.removeSource(id: id, context: context)
                try? context.save()
            }
        }

        // add to coredata
        let result: AshuraRunner.Source

        if let newSource {
            await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.createSource(source: newSource, context: context)
                try? context.save()
            }

            if
                let installedVersion = installedSource?.version,
                let breakingChangeVersion = newSource.config?.breakingChangeVersion,
                installedVersion < breakingChangeVersion
            {
                // if there was a breaking change, prompt for migration
#if !os(macOS)
                Task { @MainActor in
                    (UIApplication.shared.delegate as? AppDelegate)?.handleSourceMigration(source: newSource)
                }
#endif
            }

            result = newSource
        } else if let legacySource {
            await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.createSource(source: legacySource, context: context)
                try? context.save()
            }

            Task {
                _ = try? await legacySource.getFilters()
            }

            result = .legacy(source: legacySource)
        } else {
            return nil
        }

        sources.append(result)
        sortSources()

        NotificationCenter.default.post(name: .sourceLoaded, object: result.key)
        NotificationCenter.default.post(name: .updateSourceList, object: nil)

        return result
    }

    enum CustomSourceKind {
        case komga
        case kavita
        case suwayomi
    }

    @discardableResult
    func createCustomSource(
        kind: CustomSourceKind,
        name: String,
        server: URL,
        username: String? = nil,
        password: String? = nil,
    ) async -> String {
        let keyPrefix = switch kind {
            case .komga: KomgaSourceRunner.sourceKeyPrefix
            case .kavita: KavitaSourceRunner.sourceKeyPrefix
            case .suwayomi: SuwayomiSourceRunner.sourceKeyPrefix
        }
        let nameEncoded = name.lowercased().replacingOccurrences(of: " ", with: "-")
        var key = "\(keyPrefix).\(nameEncoded)"

        // make sure key is unique
        var counter = 1
        while SourceManager.shared.hasSourceInstalled(id: key) {
            key = "\(keyPrefix).\(nameEncoded)-\(counter)"
            counter += 1
        }

        let configValues = CustomSourceConfig.KeyNameServer(key: key, name: name, server: server.absoluteString)
        let config = switch kind {
            case .komga: CustomSourceConfig.komga(configValues)
            case .kavita: CustomSourceConfig.kavita(configValues)
            case .suwayomi: CustomSourceConfig.suwayomi(configValues)
        }
        let source = config.toSource()

        // add to coredata
        await CoreDataManager.shared.container.performBackgroundTask { context in
            let result = CoreDataManager.shared.createSource(source: source, context: context)
            result.customSource = config.encode() as NSObject
            try? context.save()
        }

        // register details
        var url = server.absoluteString
        if url.last == "/" {
            url.removeLast()
        }
        UserDefaults.standard.setValue(url, forKey: "\(key).server")
        if username != nil || password != nil {
            UserDefaults.standard.setValue("logged_in", forKey: "\(key).login")
        }
        if let username {
            UserDefaults.standard.setValue(username, forKey: "\(key).login.username")
        }
        if let password {
            UserDefaults.standard.setValue(password, forKey: "\(key).login.password")
        }

        sources.append(source)
        sortSources()

        NotificationCenter.default.post(name: .updateSourceList, object: nil)

        return key
    }

    func sortSources() {
        sources.sort { $0.name < $1.name }
        sources.sort {
            let lhs = Self.languageCodes.firstIndex(of: $0.languages.count == 1 ? $0.languages[0] : "multi") ?? Int.max
            let rhs = Self.languageCodes.firstIndex(of: $1.languages.count == 1 ? $1.languages[0] : "multi") ?? Int.max
            return lhs < rhs
        }
    }

    func clearSources() {
        let sourceKeys = sources.map { $0.key }
        for source in sources {
            guard let url = source.url else { continue }
            try? FileManager.default.removeItem(at: url)
        }
        sources = []
        Task {
            await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.clearSources(context: context)
                try? context.save()
            }
            for key in sourceKeys {
                NotificationCenter.default.post(name: .sourceUnloaded, object: key)
            }
            NotificationCenter.default.post(name: .updateSourceList, object: nil)
        }
    }

    func remove(source: AshuraRunner.Source) {
        removeSettings(from: source)
        if let url = source.url {
            try? FileManager.default.removeItem(at: url)
        }
        sources.removeAll { $0.id == source.id }
        Task {
            if source.key.hasPrefix(KomgaSourceRunner.sourceKeyPrefix) {
                await TrackerManager.komga.removeTrackItems(source: source)
            } else if source.key.hasPrefix(KavitaSourceRunner.sourceKeyPrefix) {
                await TrackerManager.kavita.removeTrackItems(source: source)
            } else if source.key.hasPrefix(SuwayomiSourceRunner.sourceKeyPrefix) {
                await TrackerManager.suwayomi.removeTrackItems(source: source)
            }
            await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.removeSource(id: source.key, context: context)
                try? context.save()
            }
            NotificationCenter.default.post(name: .sourceUnloaded, object: source.key)
            NotificationCenter.default.post(name: .updateSourceList, object: nil)
        }
    }

    func removeSettings(from source: AshuraRunner.Source) {
        let userDefaults = UserDefaults.standard
        let keys = userDefaults.dictionaryRepresentation().keys

        for key in keys where key.hasPrefix(source.key) {
            userDefaults.removeObject(forKey: key)
        }
    }

    // Pin a source in browse tab.
    func pin(source: AshuraRunner.Source) {
        let key = "Browse.pinnedList"
        var pinnedList = UserDefaults.standard.stringArray(forKey: key) ?? []
        if !pinnedList.contains(source.id) {
            pinnedList.append(source.id)
            UserDefaults.standard.set(pinnedList, forKey: key)
        }
        NotificationCenter.default.post(name: .updateSourceList, object: nil)
    }

    /// Gets a list of pinned sources.
    func getPinned() -> [AshuraRunner.Source] {
        let key = "Browse.pinnedList"
        let pinnedList = UserDefaults.standard.stringArray(forKey: key) ?? []
        return self.sources.filter { pinnedList.contains($0.id) }
    }

    // Unpin a source in browse tab.
    func unpin(source: AshuraRunner.Source) {
        let key = "Browse.pinnedList"
        var pinnedList = UserDefaults.standard.stringArray(forKey: key) ?? []
        if let index = pinnedList.firstIndex(of: source.id) {
            pinnedList.remove(at: index)
            UserDefaults.standard.set(pinnedList, forKey: key)
        }
        NotificationCenter.default.post(name: .updateSourceList, object: nil)
    }

    func updateCustomSource(key: String, config: CustomSourceConfig, updateSourceList: Bool = false) {
        Task {
            let newDbSource = await CoreDataManager.shared.container.performBackgroundTask { context in
                let source = CoreDataManager.shared.getSource(id: key, context: context)
                source?.customSource = config.encode() as NSObject
                try? context.save()
                return source?.toData()
            }
            if updateSourceList, let newSource = await newDbSource?.toNewSource() {
                await MainActor.run {
                    if let index = self.sources.firstIndex(where: { $0.id == newSource.id }) {
                        self.sources[index] = newSource
                    }
                    NotificationCenter.default.post(name: .updateSourceList, object: nil)
                }
            }
        }
    }

    // checks if a source key matches ^[A-Za-z0-9.\-]+$ and doesn't use a reserved prefix
    private func isValidSourceKey(_ sourceKey: String) -> Bool {
        guard !sourceKey.isEmpty else {
            return false
        }

        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        let allCharactersValid = sourceKey.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
        guard allCharactersValid else {
            return false
        }

        let reservedPrefixes = [
            "local",
            KomgaSourceRunner.sourceKeyPrefix,
            KavitaSourceRunner.sourceKeyPrefix,
            SuwayomiSourceRunner.sourceKeyPrefix
        ] // built-in sources
            + BackupManager.allowedSettingsPrefixes
            + BackupManager.excludedSettingsPrefixes
        let usesReservedPrefix = reservedPrefixes.contains(where: { sourceKey.hasPrefix($0) })
        guard !usesReservedPrefix else {
            return false
        }

        return true
    }
}

// MARK: - Source List Management
extension SourceManager {
    func addSourceList(url: URL) async -> Bool {
        guard !sourceListURLs.contains(url) else {
            return false
        }

        let result = await loadSourceList(url: url)
        guard let result else {
            return false
        }

        sourceLists.append(result)
        sourceListURLs.append(url)
        for source in result.sources {
            if let sourceLanguages = source.languages {
                sourceListLanguages.formUnion(sourceLanguages)
            } else if let sourceLang = source.lang {
                sourceListLanguages.insert(sourceLang)
            }
        }
        UserDefaults.standard.set(sourceListsStrings, forKey: "Browse.sourceLists")
        NotificationCenter.default.post(name: .updateSourceLists, object: nil)
        return true
    }

    func removeSourceList(url: URL) {
        sourceLists.removeAll { $0.url == url }
        sourceListURLs.removeAll { $0 == url }
        loadSourceListLanguages()
        UserDefaults.standard.set(sourceListsStrings, forKey: "Browse.sourceLists")
        NotificationCenter.default.post(name: .updateSourceLists, object: nil)
    }

    func clearSourceLists() {
        sourceLists = []
        sourceListURLs = []
        sourceListLanguages = []
        UserDefaults.standard.set([URL](), forKey: "Browse.sourceLists")
        NotificationCenter.default.post(name: .updateSourceLists, object: nil)
    }

    func loadSourceList(url: URL) async -> SourceList? {
        // set request timeout to 15s
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: config)

        guard let (data, _) = try? await session.data(from: url) else { return nil }
        let sourceList = try? JSONDecoder().decode(CodableSourceList.self, from: data)

        let result: SourceList
        if let sourceList {
            result = sourceList.into(url: url)
        } else {
            // fall back to legacy source loading
            let externalSources: [ExternalSourceInfo]? = if !url.pathExtension.isEmpty {
                try? JSONDecoder().decode([ExternalSourceInfo].self, from: data)
            } else {
                if let sources = try? await session.object(
                    from: url.appendingPathComponent("index.min.json")
                ) as [ExternalSourceInfo] {
                    sources
                } else {
                    nil
                }
            }
            guard var externalSources else { return nil }
            for index in externalSources.indices {
                externalSources[index].sourceUrl = url
            }
            result = SourceList(
                url: url,
                name: NSLocalizedString("LEGACY_SOURCE_LIST"),
                sources: externalSources,
                legacy: true
            )
        }

        return await mergeSourceStatuses(into: result, session: session)
    }

    /// Ashura: loads an optional sibling `sources-status.json` from the same base URL as the
    /// source list index (e.g. `maintenance`/`broken` badges) and merges it into the source list.
    private func mergeSourceStatuses(into sourceList: SourceList, session: URLSession) async -> SourceList {
        guard let statusURL = Self.statusListURL(for: sourceList.url) else { return sourceList }
        guard let (data, _) = try? await session.data(from: statusURL) else { return sourceList }
        guard let statuses = try? JSONDecoder().decode([SourceStatusEntry].self, from: data) else { return sourceList }

        var sourceList = sourceList
        let statusById = Dictionary(statuses.map { ($0.id, $0.status) }, uniquingKeysWith: { first, _ in first })
        sourceList.sources = sourceList.sources.map { source in
            var source = source
            if let status = statusById[source.id] {
                source.status = status
            }
            return source
        }
        return sourceList
    }

    private static func statusListURL(for listURL: URL) -> URL? {
        if listURL.pathExtension.isEmpty {
            return listURL.appendingPathComponent("sources-status.json")
        } else {
            return listURL.deletingLastPathComponent().appendingPathComponent("sources-status.json")
        }
    }

    func loadSourceListLanguages() {
        var languages = Set<String>()
        for sourceList in self.sourceLists {
            for source in sourceList.sources {
                if let sourceLanguages = source.languages {
                    languages.formUnion(sourceLanguages)
                } else if let sourceLanguage = source.lang {
                    languages.insert(sourceLanguage)
                }
            }
        }
        sourceListLanguages = languages
    }

    // MARK: Ashura: anime source list management (parallel to the manga methods above)

    func addAnimeSourceList(url: URL) async -> Bool {
        guard !animeSourceListURLs.contains(url) else {
            return false
        }

        let result = await loadSourceList(url: url)
        guard let result else {
            return false
        }

        animeSourceLists.append(result)
        animeSourceListURLs.append(url)
        for source in result.sources {
            if let sourceLanguages = source.languages {
                animeSourceListLanguages.formUnion(sourceLanguages)
            } else if let sourceLang = source.lang {
                animeSourceListLanguages.insert(sourceLang)
            }
        }
        UserDefaults.standard.set(animeSourceListsStrings, forKey: "ashura.sourceLists.anime")
        NotificationCenter.default.post(name: .updateSourceLists, object: nil)
        return true
    }

    func removeAnimeSourceList(url: URL) {
        animeSourceLists.removeAll { $0.url == url }
        animeSourceListURLs.removeAll { $0 == url }
        loadAnimeSourceListLanguages()
        UserDefaults.standard.set(animeSourceListsStrings, forKey: "ashura.sourceLists.anime")
        NotificationCenter.default.post(name: .updateSourceLists, object: nil)
    }

    func clearAnimeSourceLists() {
        animeSourceLists = []
        animeSourceListURLs = []
        animeSourceListLanguages = []
        UserDefaults.standard.set([URL](), forKey: "ashura.sourceLists.anime")
        NotificationCenter.default.post(name: .updateSourceLists, object: nil)
    }

    func loadAnimeSourceListLanguages() {
        var languages = Set<String>()
        for sourceList in animeSourceLists {
            for source in sourceList.sources {
                if let sourceLanguages = source.languages {
                    languages.formUnion(sourceLanguages)
                } else if let sourceLanguage = source.lang {
                    languages.insert(sourceLanguage)
                }
            }
        }
        animeSourceListLanguages = languages
    }
}
