//
//  StreamPlaybackViewController.swift
//  Aidoku (iOS)
//
//  Ashura: plays anime episodes directly, without opening the manga/text reader chrome.
//

import AshuraRunner
import SwiftUI
import UIKit

/// Loads a chapter's pages, resolves which stream quality to play (asking the user only
/// when necessary), then embeds `VideoPlayerViewController` full screen. Used for `.anime`
/// sources so watching an episode doesn't route through the manga reader.
class StreamPlaybackViewController: UIViewController {
    private let source: AshuraRunner.Source?
    private let manga: AshuraRunner.Manga
    private let chapter: AshuraRunner.Chapter

    private var playerNavigationController: UINavigationController?

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    init(source: AshuraRunner.Source?, manga: AshuraRunner.Manga, chapter: AshuraRunner.Chapter) {
        self.source = source
        self.manga = manga
        self.chapter = chapter
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        activityIndicator.startAnimating()

        Task {
            await loadAndPlay()
        }
    }

    private func loadAndPlay() async {
        let sourceId = source?.key ?? manga.sourceKey
        let ashuraPages = (try? await source?.getPageList(manga: manga, chapter: chapter)) ?? []
        let pages = ashuraPages.map { $0.toOld(sourceId: sourceId, chapterId: chapter.key) }
        let streamPages = pages.filter(\.isStreamPage)

        guard !streamPages.isEmpty else {
            showLoadFailAlertAndDismiss()
            return
        }

        // Always offer a quality sheet when there are multiple streams, so tapping an
        // episode never drops the user into the manga reader first. Preferred quality is
        // remembered and used as the default pick order next time via StreamQualityStore.
        if streamPages.count > 1 {
            presentQualityPicker(streamPages)
        } else if let only = streamPages.first {
            if let quality = only.streamQuality {
                StreamQualityStore.setPreferredQuality(quality)
            }
            play(only)
        } else {
            showLoadFailAlertAndDismiss()
        }
    }

    private func presentQualityPicker(_ streamPages: [Page]) {
        activityIndicator.stopAnimating()

        // Put preferred / best-match first so the remembered choice is easy to tap.
        let preferred = StreamQualityStore.pick(from: streamPages)
        var ordered = streamPages
        if let preferred, let idx = ordered.firstIndex(where: { $0.streamURL == preferred.streamURL }) {
            ordered.remove(at: idx)
            ordered.insert(preferred, at: 0)
        }

        let sheet = UIAlertController(
            title: NSLocalizedString("SELECT_QUALITY", comment: ""),
            message: nil,
            preferredStyle: .actionSheet
        )
        for page in ordered {
            var label = page.streamQuality ?? page.streamURL ?? "Stream"
            if page.streamURL == preferred?.streamURL {
                label += " ★"
            }
            sheet.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                if let quality = page.streamQuality {
                    StreamQualityStore.setPreferredQuality(quality)
                }
                self?.play(page)
            })
        }
        sheet.addAction(UIAlertAction(title: NSLocalizedString("CANCEL", comment: ""), style: .cancel) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(sheet, animated: true)
    }

    private func play(_ page: Page) {
        activityIndicator.stopAnimating()
        guard let urlString = page.streamURL, let url = URL(string: urlString) else {
            showLoadFailAlertAndDismiss()
            return
        }

        let progressKey = ContinueWatchingStore.makeKey(
            sourceId: manga.sourceKey,
            mangaId: manga.key,
            chapterId: chapter.key
        )
        let startPosition = ContinueWatchingStore.progress(key: progressKey)?.position ?? 0
        let titleSuffix = page.streamQuality.map { " (\($0))" } ?? ""
        let player = VideoPlayerViewController(
            streamURL: url,
            headers: page.streamHeaders,
            title: (chapter.title ?? manga.title) + titleSuffix,
            startPosition: startPosition,
            progressKey: progressKey
        )
        player.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(donePlaying)
        )

        let nav = UINavigationController(rootViewController: player)
        nav.overrideUserInterfaceStyle = .dark
        embed(nav)
    }

    private func embed(_ nav: UINavigationController) {
        addChild(nav)
        nav.view.frame = view.bounds
        nav.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        nav.view.backgroundColor = .black
        view.addSubview(nav.view)
        nav.didMove(toParent: self)
        playerNavigationController = nav
    }

    @objc private func donePlaying() {
        dismiss(animated: true)
    }

    private func showLoadFailAlertAndDismiss() {
        activityIndicator.stopAnimating()
        let alert = UIAlertController(
            title: NSLocalizedString("FAILED_CHAPTER_LOAD", comment: ""),
            message: NSLocalizedString("FAILED_CHAPTER_LOAD_INFO", comment: ""),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }
}

/// SwiftUI wrapper around `StreamPlaybackViewController`, mirroring `SwiftUIReaderNavigationController`.
struct SwiftUIStreamPlayerController: View {
    let source: AshuraRunner.Source?
    let manga: AshuraRunner.Manga
    let chapter: AshuraRunner.Chapter

    var body: some View {
        _SwiftUIStreamPlayerController(source: source, manga: manga, chapter: chapter)
    }
}

private struct _SwiftUIStreamPlayerController: UIViewControllerRepresentable {
    let source: AshuraRunner.Source?
    let manga: AshuraRunner.Manga
    let chapter: AshuraRunner.Chapter

    final class Coordinator {
        var controller: StreamPlaybackViewController?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> StreamPlaybackViewController {
        if let controller = context.coordinator.controller { return controller }

        let controller = StreamPlaybackViewController(
            source: source,
            manga: manga,
            chapter: chapter
        )
        context.coordinator.controller = controller
        return controller
    }

    func updateUIViewController(_ uiViewController: StreamPlaybackViewController, context: Context) {
        // playback is set up once in viewDidLoad; SwiftUI presents a fresh instance whenever
        // the fullScreenCover's `chapter` item identity changes.
    }
}
