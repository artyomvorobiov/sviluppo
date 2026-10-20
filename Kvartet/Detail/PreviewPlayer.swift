import AVFoundation
import AVKit
import Observation
import SwiftUI

/// Проигрывает 30-секундный фрагмент ключевого трека альбома (iTunes preview).
@MainActor
@Observable
final class PreviewPlayer {
    enum PlaybackState: Equatable {
        case idle
        case loading
        case playing
        case paused
        case unavailable
    }

    private(set) var state: PlaybackState = .idle
    private(set) var progress: Double = 0

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    func toggle(item: Item) async {
        switch state {
        case .playing:
            player?.pause()
            state = .paused
        case .paused:
            player?.play()
            state = .playing
        case .loading, .unavailable:
            return
        case .idle:
            state = .loading
            guard let url = await MediaResolver.shared.previewURL(for: item) else {
                state = .unavailable
                return
            }
            guard state == .loading else { return }
            start(url)
        }
    }

    func stop() {
        player?.pause()
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        timeObserver = nil
        endObserver = nil
        player = nil
        if state != .unavailable {
            state = .idle
        }
        progress = 0
    }

    private func start(_ url: URL) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        let player = AVPlayer(url: url)
        self.player = player
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, let duration = self.player?.currentItem?.duration.seconds,
                      duration.isFinite, duration > 0
                else { return }
                self.progress = min(1, time.seconds / duration)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stop()
            }
        }
        player.play()
        state = .playing
    }
}

/// Кнопка фрагмента с прогрессом.
struct PreviewButton: View {
    let item: Item
    let player: PreviewPlayer

    var body: some View {
        Button {
            Task { await player.toggle(item: item) }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(item.kind.color.opacity(0.14))
                    if player.state == .loading {
                        ProgressView()
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(item.kind.color)
                    }
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 5) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("«\(item.keyTrack ?? "")»")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    ProgressView(value: player.progress)
                        .tint(item.kind.color)
                        .opacity(player.state == .playing || player.state == .paused ? 1 : 0)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(player.state == .unavailable)
        .accessibilityLabel(Text("\(subtitle): \(item.keyTrack ?? "")"))
    }

    private var icon: String {
        switch player.state {
        case .playing: "pause.fill"
        case .unavailable: "speaker.slash"
        default: "play.fill"
        }
    }

    private var subtitle: String {
        player.state == .unavailable ? "Фрагмент не найден — откройте альбом в сервисе" : "С чего начать · 30 секунд"
    }
}

/// Трейлер фильма из iTunes.
struct TrailerPlayerView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }
            CloseButton { dismiss() }
                .padding()
        }
        .onAppear {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            let player = AVPlayer(url: url)
            self.player = player
            player.play()
        }
        .onDisappear {
            player?.pause()
        }
    }
}
