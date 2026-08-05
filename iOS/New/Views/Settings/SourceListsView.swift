//
//  SourceListsView.swift
//  Aidoku
//
//  Created by Skitty on 6/5/25.
//

import SwiftUI

struct SourceListsView: View {
    @State private var mediaKind: AppMediaKind = MediaKindPreferences.browseMediaKind

    @State private var sourceLists: [SourceList] = []
    @State private var missingSourceLists: [URL] = []

    @State private var loading = false
    @State private var showAddListFailAlert = false

    private var sourceListURLs: [URL] {
        mediaKind == .anime ? SourceManager.shared.animeSourceListURLs : SourceManager.shared.sourceListURLs
    }

    private var currentSourceLists: [SourceList] {
        mediaKind == .anime ? SourceManager.shared.animeSourceLists : SourceManager.shared.sourceLists
    }

    var body: some View {
        List {
            Section {
                Picker("", selection: $mediaKind) {
                    Text(NSLocalizedString("SOURCE_LISTS_MANGA", comment: "")).tag(AppMediaKind.manga)
                    Text(NSLocalizedString("SOURCE_LISTS_ANIME", comment: "")).tag(AppMediaKind.anime)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .padding(.vertical, 4)
            }

            Section {
                ForEach(sourceLists, id: \.url) { sourceList in
                    listItem(name: sourceList.name, url: sourceList.url)
                }
                .onDelete(perform: delete)
            }

            if !missingSourceLists.isEmpty {
                Section {
                    ForEach(missingSourceLists, id: \.self) { url in
                        listItem(url: url)
                    }
                } header: {
                    Text(NSLocalizedString("UNAVAILABLE_SOURCE_LISTS"))
                } footer: {
                    Text(NSLocalizedString("UNAVAILABLE_SOURCE_LISTS_TEXT"))
                }
            }
        }
        .overlay {
            if loading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.secondary)
            }
        }
        .navigationTitle(NSLocalizedString("SOURCE_LISTS"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAlert()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert(NSLocalizedString("SOURCE_LIST_ADD_FAIL"), isPresented: $showAddListFailAlert) {
            Button(NSLocalizedString("OK"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("SOURCE_LIST_ADD_FAIL_TEXT"))
        }
        .onChange(of: mediaKind) { newValue in
            MediaKindPreferences.browseMediaKind = newValue
            refreshLists()
            Task {
                if currentSourceLists.isEmpty && !sourceListURLs.isEmpty {
                    loading = true
                    await loadCurrentLists()
                    loading = false
                    refreshLists()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateSourceLists)) { _ in
            withAnimation {
                loading = false
                refreshLists()
            }
        }
        .task {
            if currentSourceLists.isEmpty {
                loading = true
                await loadCurrentLists()
                loading = false
            }
            refreshLists()
        }
    }

    private func loadCurrentLists() async {
        if mediaKind == .anime {
            await SourceManager.shared.loadAnimeSourceLists()
        } else {
            await SourceManager.shared.loadSourceLists()
        }
    }

    private func refreshLists() {
        sourceLists = currentSourceLists
        if sourceListURLs.count != sourceLists.count {
            missingSourceLists = sourceListURLs.filter { url in
                !sourceLists.contains(where: { $0.url == url })
            }
        } else {
            missingSourceLists = []
        }
    }

    func listItem(name: String? = nil, url: URL) -> some View {
        VStack(alignment: .leading) {
            if let name {
                Text(name)
            }
            Text(url.absoluteString)
                .lineLimit(1)
                .font(.subheadline)
                .foregroundStyle(name == nil ? .primary : .secondary)
        }
        .contextMenu {
            Button(role: .destructive) {
                sourceLists.firstIndex(where: { $0.url == url }).flatMap {
                    _ = sourceLists.remove(at: $0)
                }
                missingSourceLists.firstIndex(of: url).flatMap {
                    _ = missingSourceLists.remove(at: $0)
                }
                removeSourceList(url: url)
            } label: {
                Label(NSLocalizedString("REMOVE"), systemImage: "trash")
            }
            Button {
                UIPasteboard.general.string = url.absoluteString
            } label: {
                Label(NSLocalizedString("COPY_URL"), systemImage: "doc.on.doc")
            }
        }
    }

    private func removeSourceList(url: URL) {
        if mediaKind == .anime {
            SourceManager.shared.removeAnimeSourceList(url: url)
        } else {
            SourceManager.shared.removeSourceList(url: url)
        }
    }

    func delete(at offsets: IndexSet) {
        let urls = offsets.map { sourceLists[$0].url }
        for url in urls {
            removeSourceList(url: url)
        }
    }

    func addSourceList(url: String) {
        guard !url.isEmpty else { return }
        guard let url = URL(string: url) else {
            showAddListFailAlert = true
            return
        }

        actor Done {
            var value: Bool = false
            func set() {
                value = true
            }
        }
        let done = Done()
        let mediaKind = self.mediaKind

        Task {
            // show loading indicator if it takes longer than 0.5s
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let finished = await done.value
                if !finished {
                    await MainActor.run {
                        (UIApplication.shared.delegate as? AppDelegate)?.showLoadingIndicator()
                    }
                }
            }

            let success = if mediaKind == .anime {
                await SourceManager.shared.addAnimeSourceList(url: url)
            } else {
                await SourceManager.shared.addSourceList(url: url)
            }
            await done.set()
            await (UIApplication.shared.delegate as? AppDelegate)?.hideLoadingIndicator()

            if success {
                withAnimation {
                    refreshLists()
                }
            } else {
                showAddListFailAlert = true
            }
        }
    }

    func showAlert() {
        var alertTextField: UITextField?
        (UIApplication.shared.delegate as? AppDelegate)?.presentAlert(
            title: NSLocalizedString("SOURCE_LIST_ADD"),
            message: NSLocalizedString("SOURCE_LIST_ADD_TEXT"),
            actions: [
                UIAlertAction(title: NSLocalizedString("CANCEL"), style: .cancel),
                UIAlertAction(title: NSLocalizedString("OK"), style: .default) { _ in
                    guard let text = alertTextField?.text, !text.isEmpty else { return }
                    addSourceList(url: text)
                }
            ],
            textFieldHandlers: [
                { textField in
                    textField.placeholder = NSLocalizedString("SOURCE_LIST_URL")
                    textField.keyboardType = .URL
                    textField.autocorrectionType = .no
                    textField.autocapitalizationType = .none
                    textField.returnKeyType = .done
                    alertTextField = textField
                }
            ]
        )
    }
}

#Preview {
    SourceListsView()
}
