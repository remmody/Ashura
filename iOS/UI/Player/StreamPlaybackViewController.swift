//
//  StreamPlaybackViewController.swift
//  Aidoku (iOS)
//
//  Ashura: plays anime episodes directly, without opening the manga/text reader chrome.
//

import AshuraRunner
import SwiftUI
import UIKit

/// Loads a chapter's stream pages, auto-picks preferred/best quality (Sora-style), then
/// presents `VideoPlayerViewController`. Quality can be changed from inside the player —
/// there is no blocking action-sheet that races with playback.
class StreamPlaybackViewController: UIViewController {
    private let source: AshuraRunner.Source?
    private let manga: AshuraRunner.Manga
    private let chapter: AshuraRunner.Chapter

    private var didStartLoad = false
    private var embeddedPlayer: VideoPlayerViewController?

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

        guard !didStartLoad else { return }
        didStartLoad = true
        Task {
            await loadAndPlay()
        }
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    private func loadAndPlay() async {
        let sourceId = source?.key ?? manga.sourceKey
        let ashuraPages = (try? await source?.getPageList(manga: manga, chapter: chapter)) ?? []
        let pages = ashuraPages.map { $0.toOld(sourceId: sourceId, chapterId: chapter.key) }
        let streamPages = pages.filter(\.isStreamPage)

        guard !streamPages.isEmpty else {
            await MainActor.run { showLoadFailAlertAndDismiss() }
            return
        }

        // Auto-pick remembered / best available quality — never open a sheet under a playing video.
        guard let picked = StreamQualityStore.pick(from: streamPages),
              let pickedURL = picked.streamURL.flatMap(URL.init(string:))
        else {
            await MainActor.run { showLoadFailAlertAndDismiss() }
            return
        }

        let options: [VideoPlayerViewController.StreamOption] = streamPages.compactMap { page in
            guard let urlString = page.streamURL, let url = URL(string: urlString) else { return nil }
            return .init(url: url, quality: page.streamQuality, headers: page.streamHeaders)
        }
        let initialIndex = options.firstIndex(where: { $0.url.absoluteString == pickedURL.absoluteString }) ?? 0

        let progressKey = ContinueWatchingStore.makeKey(
            sourceId: manga.sourceKey,
            mangaId: manga.key,
            chapterId: chapter.key
        )
        let startPosition = ContinueWatchingStore.progress(key: progressKey)?.position ?? 0

        await MainActor.run {
            activityIndicator.stopAnimating()
            presentPlayer(
                options: options,
                initialIndex: initialIndex,
                startPosition: startPosition,
                progressKey: progressKey
            )
        }
    }

    private func presentPlayer(
        options: [VideoPlayerViewController.StreamOption],
        initialIndex: Int,
        startPosition: Double,
        progressKey: String
    ) {
        // Replace any previous embed (SwiftUI can recreate the host unexpectedly).
        if let embeddedPlayer {
            embeddedPlayer.willMove(toParent: nil)
            embeddedPlayer.view.removeFromSuperview()
            embeddedPlayer.removeFromParent()
            self.embeddedPlayer = nil
        }

        let player = VideoPlayerViewController(
            streams: options,
            initialIndex: initialIndex,
            title: chapter.title ?? manga.title,
            startPosition: startPosition,
            progressKey: progressKey
        )
        player.onClose = { [weak self] in
            self?.dismiss(animated: true)
        }

        addChild(player)
        player.view.frame = view.bounds
        player.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(player.view)
        player.didMove(toParent: self)
        embeddedPlayer = player
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
            .ignoresSafeArea()
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
        // Playback is set up once; identity changes recreate this representable via fullScreenCover.
    }
}
