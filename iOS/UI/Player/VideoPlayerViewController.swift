//
//  VideoPlayerViewController.swift
//  Aidoku (iOS)
//
//  Ashura: minimal AVKit-based video player shell for anime streaming sources.
//

import AVFoundation
import AVKit
import UIKit

/// A basic AVKit video player used to present `PageContent.stream` pages (anime episodes).
///
/// This is an initial scaffold for phase4 video playback: it supports custom request headers
/// (e.g. referer/auth tokens required by some streaming sources) and periodically persists
/// playback position via `ContinueWatchingStore` so viewing can resume later.
class VideoPlayerViewController: AVPlayerViewController {
    private let streamURL: URL
    private let streamHeaders: [String: String]?
    private let progressKey: String?
    private let startPosition: Double

    private var timeObserverToken: Any?
    private let progressSaveInterval: TimeInterval = 5

    /// - Parameters:
    ///   - streamURL: direct URL of the video stream to play.
    ///   - headers: optional HTTP headers (e.g. referer, auth) required to fetch the stream.
    ///   - title: optional display title, shown in the player UI when supported.
    ///   - startPosition: playback position (seconds) to seek to on load, e.g. from resumed history.
    ///   - progressKey: identifier used to persist/restore watch progress via `ContinueWatchingStore`.
    ///     Defaults to the stream URL's absolute string when not provided.
    init(
        streamURL: URL,
        headers: [String: String]? = nil,
        title: String? = nil,
        startPosition: Double = 0,
        progressKey: String? = nil
    ) {
        self.streamURL = streamURL
        self.streamHeaders = headers
        self.startPosition = startPosition
        self.progressKey = progressKey ?? title ?? streamURL.absoluteString
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpPlayer()
    }

    deinit {
        if let timeObserverToken {
            player?.removeTimeObserver(timeObserverToken)
        }
    }

    private func setUpPlayer() {
        // Ashura: many streaming CDNs serve silent/failing responses without a browser-like
        // User-Agent, and playback stays silent unless the app's audio session is configured
        // for media playback (it defaults to a category that can leave audio muted/ducked).
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)

        var headers = streamHeaders ?? [:]
        if !headers.keys.contains(where: { $0.caseInsensitiveCompare("User-Agent") == .orderedSame }) {
            headers["User-Agent"] = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"
        }

        let asset = AVURLAsset(
            url: streamURL,
            options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
        )
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        self.player = player

        let resumePosition = startPosition > 0
            ? startPosition
            : (progressKey.flatMap { ContinueWatchingStore.progress(key: $0)?.position } ?? 0)
        if resumePosition > 0 {
            player.seek(to: CMTime(seconds: resumePosition, preferredTimescale: 600))
        }

        addPeriodicProgressObserver(to: player)
        player.play()
    }

    private func addPeriodicProgressObserver(to player: AVPlayer) {
        let interval = CMTime(seconds: progressSaveInterval, preferredTimescale: 1)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.saveProgress(currentTime: time)
        }
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
}
