//
//  MediaKindStrings.swift
//  Aidoku
//
//  Ashura: localized chapter vs episode strings based on media kind.
//

import AshuraRunner
import Foundation

enum MediaKindStrings {
    enum Key {
        case unit
        case units
        case unitX
        case shortX
        case shortSpaceX
        case downloadedUnits
        case noUnits
        case noUnitsAvailable
        case startAction
        case continueAction
        case selectUnits
        case countUnits
        case oneUnit
        case unitPlural
        case unitSingular
        case allUnitsRead
        case allUnitsLocked
        case unitForward
        case unitBackward
    }

    static func localized(_ key: Key, mediaKind: AppMediaKind) -> String {
        NSLocalizedString(localizationKey(for: key, mediaKind: mediaKind))
    }

    static func localized(_ key: Key, mediaKind: AshuraRunner.MediaKind?) -> String {
        localized(key, mediaKind: AppMediaKind(mediaKind))
    }

    static func localized(_ key: Key, source: AshuraRunner.Source?) -> String {
        localized(key, mediaKind: source?.mediaKind)
    }

    static func localizationKey(for key: Key, mediaKind: AppMediaKind) -> String {
        switch (key, mediaKind) {
            case (.unit, .manga): "CHAPTER"
            case (.unit, .anime): "EPISODE"
            case (.units, .manga): "CHAPTERS"
            case (.units, .anime): "EPISODES"
            case (.unitX, .manga): "CHAPTER_X"
            case (.unitX, .anime): "EPISODE_X"
            case (.shortX, .manga): "CH_X"
            case (.shortX, .anime): "EP_X"
            case (.shortSpaceX, .manga): "CH_SPACE_X"
            case (.shortSpaceX, .anime): "EP_SPACE_X"
            case (.downloadedUnits, .manga): "DOWNLOADED_CHAPTERS"
            case (.downloadedUnits, .anime): "DOWNLOADED_EPISODES"
            case (.noUnits, .manga): "NO_CHAPTERS"
            case (.noUnits, .anime): "NO_EPISODES"
            case (.noUnitsAvailable, .manga): "NO_CHAPTERS_AVAILABLE"
            case (.noUnitsAvailable, .anime): "NO_EPISODES_AVAILABLE"
            case (.startAction, .manga): "START_READING"
            case (.startAction, .anime): "START_WATCHING"
            case (.continueAction, .manga): "CONTINUE_READING"
            case (.continueAction, .anime): "CONTINUE_WATCHING"
            case (.selectUnits, .manga): "SELECT_CHAPTERS"
            case (.selectUnits, .anime): "SELECT_EPISODES"
            case (.countUnits, .manga): "%i_CHAPTERS"
            case (.countUnits, .anime): "%i_EPISODES"
            case (.oneUnit, .manga): "1_CHAPTER"
            case (.oneUnit, .anime): "1_EPISODE"
            case (.unitPlural, .manga): "CHAPTER_PLURAL"
            case (.unitPlural, .anime): "EPISODE_PLURAL"
            case (.unitSingular, .manga): "CHAPTER_SINGULAR"
            case (.unitSingular, .anime): "EPISODE_SINGULAR"
            case (.allUnitsRead, .manga): "ALL_CHAPTERS_READ"
            case (.allUnitsRead, .anime): "ALL_EPISODES_READ"
            case (.allUnitsLocked, .manga): "ALL_CHAPTERS_LOCKED"
            case (.allUnitsLocked, .anime): "ALL_EPISODES_LOCKED"
            case (.unitForward, .manga): "CHAPTER_FORWARD"
            case (.unitForward, .anime): "EPISODE_FORWARD"
            case (.unitBackward, .manga): "CHAPTER_BACKWARD"
            case (.unitBackward, .anime): "EPISODE_BACKWARD"
        }
    }
}

extension AppMediaKind {
    init(_ mediaKind: AshuraRunner.MediaKind?) {
        self = AppMediaKind(rawValue: mediaKind?.rawValue ?? AshuraRunner.MediaKind.manga.rawValue) ?? .manga
    }
}
