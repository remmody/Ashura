//
//  Page.swift
//  Aidoku
//
//  Created by Skitty on 12/22/21.
//

import Foundation
import AshuraRunner

struct Page: Hashable {

    enum PageType: Int {
        case imagePage
        case prevInfoPage
        case nextInfoPage
    }

    var type: PageType = .imagePage
    var sourceId: String
    var chapterId: String
    var index: Int = 0
    var imageURL: String?
    var base64: String?
    var text: String?
    var image: PlatformImage?
    var zipURL: String?

    // Ashura: video stream page support
    var streamURL: String?
    var streamHeaders: [String: String]?
    var streamMime: String?

    var context: PageContext?
    var hasDescription: Bool = false
    var description: String?

    var key: String {
        "\(chapterId)|\(index)"
    }

    var isTextPage: Bool {
        text != nil || (zipURL != nil && imageURL?.lowercased().hasSuffix(".txt") == true)
    }

    /// Ashura: whether this page represents a video stream rather than an image/text page.
    var isStreamPage: Bool {
        streamURL != nil
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(chapterId)
        hasher.combine(index)
    }
}

extension Page {
    func toNew() -> AshuraRunner.Page {
        let content: AshuraRunner.PageContent = if let imageURL, let url = URL(string: imageURL) {
            .url(url: url, context: context)
        } else if let text {
            .text(text)
        } else if let image {
#if os(macOS)
            .image(AshuraRunner.PlatformImage(image))
#else
            .image(image)
#endif
        } else if let zipURL, let url = URL(string: zipURL), let imageURL {
            .zipFile(url: url, filePath: imageURL)
        } else if let streamURL, let url = URL(string: streamURL) {
            .stream(AshuraRunner.StreamInfo(url: url, headers: streamHeaders, mime: streamMime))
        } else {
            .text("Invalid URL")
        }
        return AshuraRunner.Page(
            content: content,
            hasDescription: hasDescription,
            description: description
        )
    }
}
