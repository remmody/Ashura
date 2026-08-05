//
//  VideoPlayerViewController.swift
//  Aidoku (iOS)
//
//  Ashura: AVKit video player shell for anime streaming sources.
//  UX modeled on Sora: auto-start preferred quality, in-player quality menu,
//  and an explicit close (X) control — never a nav-bar "Done" checkmark.
//

import AVFoundation
import AVKit
import UIKit

/// Presents anime episode streams with Sora-like chrome:
/// - system AVKit playback controls
/// - close button (top-leading)
/// - quality menu (top-trailing) when multiple streams are available
/// - progress persistence via `ContinueWatchingStore`
class VideoPlayerViewController: UIViewController {
    struct StreamOption {
        let url: URL
        let quality: String?
        let headers: [String: String]?
    }

    private var streams: [StreamOption]
    private var currentIndex: Int
    private let progressKey: String?
    private let startPosition: Double
    private let episodeTitle: String?

    /// Called when the user taps close — parent should dismiss the whole playback cover.
    var onClose: (() -> Void)?

    private var player: AVPlayer?
    private var playerViewController: AVPlayerViewController?
    private var timeObserverToken: Any?
    private let progressSaveInterval: TimeInterval = 5

    private lazy var closeButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "xmark")
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        config.baseForegroundColor = .white
        config.background.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        config.background.cornerRadius = 21
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = NSLocalizedString("CLOSE", comment: "")
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        return button
    }()

    private lazy var qualityButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "rectangle.stack")
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        config.baseForegroundColor = .white
        config.background.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        config.background.cornerRadius = 21
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.showsMenuAsPrimaryAction = true
        button.isHidden = true
        button.accessibilityLabel = NSLocalizedString("SELECT_QUALITY", comment: "")
        return button
    }()

    init(
        streams: [StreamOption],
        initialIndex: Int = 0,
        title: String? = nil,
        startPosition: Double = 0,
        progressKey: String? = nil
    ) {
        self.streams = streams
        self.currentIndex = min(max(0, initialIndex), max(0, streams.count - 1))
        self.episodeTitle = title
        self.startPosition = startPosition
        self.progressKey = progressKey ?? title ?? streams.first?.url.absoluteString
        super.init(nibName: nil, bundle: nil)
        self.title = title
        modalPresentationStyle = .fullScreen
    }

    /// Convenience for a single stream (legacy call sites).
    convenience init(
        streamURL: URL,
        headers: [String: String]? = nil,
        title: String? = nil,
        startPosition: Double = 0,
        progressKey: String? = nil,
        quality: String? = nil
    ) {
        self.init(
            streams: [StreamOption(url: streamURL, quality: quality, headers: headers)],
            initialIndex: 0,
            title: title,
            startPosition: startPosition,
            progressKey: progressKey
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        removeTimeObserver()
        player?.pause()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overrideUserInterfaceStyle = .dark

        embedPlayerChrome()
        loadCurrentStream(seekTo: nil, autoplay: true)
        refreshQualityMenu()
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // MARK: - Layout

    private func embedPlayerChrome() {
        let pvc = AVPlayerViewController()
        pvc.showsPlaybackControls = true
        pvc.allowsPictureInPicturePlayback = true
        if #available(iOS 16.0, *) {
            pvc.allowsVideoFrameAnalysis = false
        }
        addChild(pvc)
        pvc.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pvc.view)
        NSLayoutConstraint.activate([
            pvc.view.topAnchor.constraint(equalTo: view.topAnchor),
            pvc.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pvc.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pvc.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        pvc.didMove(toParent: self)
        playerViewController = pvc

        view.addSubview(closeButton)
        view.addSubview(qualityButton)
        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.widthAnchor.constraint(equalToConstant: 42),
            closeButton.heightAnchor.constraint(equalToConstant: 42),

            qualityButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            qualityButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            qualityButton.widthAnchor.constraint(equalToConstant: 42),
            qualityButton.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    // MARK: - Playback

    private func loadCurrentStream(seekTo position: Double?, autoplay: Bool) {
        guard streams.indices.contains(currentIndex) else { return }
        let option = streams[currentIndex]

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)

        var headers = option.headers ?? [:]
        if !headers.keys.contains(where: { $0.caseInsensitiveCompare("User-Agent") == .orderedSame }) {
            headers["User-Agent"] = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"
        }

        removeTimeObserver()

        let asset = AVURLAsset(
            url: option.url,
            options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
        )
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        self.player = player
        playerViewController?.player = player

        let resumePosition = position
            ?? (startPosition > 0
                ? startPosition
                : (progressKey.flatMap { ContinueWatchingStore.progress(key: $0)?.position } ?? 0))
        if resumePosition > 1 {
            player.seek(to: CMTime(seconds: resumePosition, preferredTimescale: 600))
        }

        addPeriodicProgressObserver(to: player)
        if autoplay {
            player.play()
        }

        if let quality = option.quality {
            StreamQualityStore.setPreferredQuality(quality)
        }
        refreshTitle()
    }

    private func refreshTitle() {
        let quality = streams[safe: currentIndex]?.quality
        let suffix = quality.map { " (\($0))" } ?? ""
        let base = episodeTitle ?? ""
        title = base.isEmpty ? quality : base + suffix
        playerViewController?.title = title
    }

    private func switchQuality(to index: Int) {
        guard streams.indices.contains(index), index != currentIndex else { return }
        let position = player?.currentTime().seconds ?? 0
        currentIndex = index
        loadCurrentStream(seekTo: position > 1 ? position : nil, autoplay: true)
        refreshQualityMenu()
    }

    private func refreshQualityMenu() {
        guard streams.count > 1 else {
            qualityButton.isHidden = true
            qualityButton.menu = nil
            return
        }
        qualityButton.isHidden = false
        let actions = streams.enumerated().map { index, option in
            let label = option.quality ?? option.url.lastPathComponent
            return UIAction(
                title: label,
                state: index == currentIndex ? .on : .off
            ) { [weak self] _ in
                self?.switchQuality(to: index)
            }
        }
        qualityButton.menu = UIMenu(
            title: NSLocalizedString("SELECT_QUALITY", comment: ""),
            options: .displayInline,
            children: actions
        )
    }

    // MARK: - Progress

    private func addPeriodicProgressObserver(to player: AVPlayer) {
        let interval = CMTime(seconds: progressSaveInterval, preferredTimescale: 1)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.saveProgress(currentTime: time)
        }
    }

    private func removeTimeObserver() {
        if let timeObserverToken, let player {
            player.removeTimeObserver(timeObserverToken)
        }
        timeObserverToken = nil
    }

    private func saveProgress(currentTime: CMTime) {
        guard
            let progressKey,
            let duration = player?.currentItem?.duration,
            duration.isNumeric,
            duration.seconds > 0
        else {
            return
        }
        ContinueWatchingStore.save(
            key: progressKey,
            title: title,
            position: currentTime.seconds,
            duration: duration.seconds
        )
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        player?.pause()
        if let onClose {
            onClose()
        } else {
            dismiss(animated: true)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
