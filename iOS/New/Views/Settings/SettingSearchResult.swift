//
//  SettingSearchResult.swift
//  Aidoku
//
//  Created by Skitty on 9/19/25.
//

import AshuraRunner
import SwiftUI

struct SettingPath {
    let key: String
    let title: String
    let paths: [String]
    var setting: AshuraRunner.Setting?
}

struct SettingSearchResult {
    var sections: [Section]

    struct Section: Identifiable {
        let id = UUID()
        var icon: AshuraRunner.PageSetting.Icon?
        var header: String?
        var paths: [SettingPath]
    }
}
