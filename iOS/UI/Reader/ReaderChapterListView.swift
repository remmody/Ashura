//
//  ReaderChapterListView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/20/22.
//

import SwiftUI
import AshuraRunner

struct ReaderChapterListView: View {
    var chapterList: [AshuraRunner.Chapter]
    @State var chapter: AshuraRunner.Chapter
    var mediaKind: AppMediaKind = .manga
    var chapterSet: ((AshuraRunner.Chapter) -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PlatformNavigationStack {
            ScrollViewReader { proxy in
                List(chapterList) { chapter in
                    Button {
                        self.chapter = chapter
                        chapterSet?(chapter)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(displayString(for: chapter))
                                    .foregroundColor(.primary)
                                    .font(.subheadline)
                                if let title = chapter.title, chapter.chapterNumber != nil || chapter.volumeNumber != nil {
                                    Text(title)
                                        .foregroundColor(.secondary)
                                        .font(.subheadline)
                                }
                            }
                            Spacer()
                            if chapter == self.chapter {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .id(chapter.id)
                }
                .onAppear {
                    proxy.scrollTo(chapter.id, anchor: .center)
                }
            }
            .navigationTitle(MediaKindStrings.localized(.units, mediaKind: mediaKind))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton {
                        dismiss()
                    }
                }
            }
        }
    }

    private func displayString(for chapter: AshuraRunner.Chapter) -> String {
        if let chapterNum = chapter.chapterNumber {
            if let volumeNum = chapter.volumeNumber {
                String(
                    format: NSLocalizedString("VOL_X", comment: "")
                        + " "
                        + MediaKindStrings.localized(.shortX, mediaKind: mediaKind),
                    volumeNum,
                    chapterNum
                )
            } else {
                String(format: MediaKindStrings.localized(.unitX, mediaKind: mediaKind), chapterNum)
            }
        } else if let volumeNum = chapter.volumeNumber {
            String(format: NSLocalizedString("VOLUME_X", comment: ""), volumeNum)
        } else {
            chapter.title ?? ""
        }
    }
}
