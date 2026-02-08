import SwiftUI
import AVKit
import AppKit

// View de fundo que apenas mostra o vídeo (sem mexer em scroll).
// Implementada com AVPlayerLayer (e não AVPlayerView) para evitar que o
// macOS registre o player no sistema de mídia (Control Center, teclas
// globais de play/pause, etc.).
struct VideoBackgroundView: NSViewRepresentable {
    let player: AVPlayer

    final class PlayerLayerView: NSView {
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            configureLayer()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            configureLayer()
        }

        private func configureLayer() {
            wantsLayer = true
            // Garante que SEMPRE usamos um AVPlayerLayer (e não o CALayer padrão
            // criado automaticamente pelo wantsLayer).
            let playerLayer = AVPlayerLayer()
            playerLayer.videoGravity = .resizeAspect
            playerLayer.backgroundColor = NSColor.black.cgColor
            layer = playerLayer
        }

        override func layout() {
            super.layout()
            // Garante que o AVPlayerLayer sempre ocupe toda a área da view.
            if let l = layer as? AVPlayerLayer {
                l.frame = bounds
            }
        }

        var player: AVPlayer? {
            get { (layer as? AVPlayerLayer)?.player }
            set { (layer as? AVPlayerLayer)?.player = newValue }
        }
    }

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerLayerView, context: Context) {
        nsView.player = player
    }
}

// NSView transparente só para capturar eventos de scroll e repassar para SwiftUI.
final class ScrollCaptureNSView: NSView {
    var onScroll: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        if Paths.isDevelopment {
            print("[ScrollCapture] scrollWheel dx=\(event.scrollingDeltaX), dy=\(event.scrollingDeltaY), inverted=\(event.isDirectionInvertedFromDevice)")
        }
        onScroll?(event)
        // Não chamamos super, para não deixar outros componentes mexerem no tempo.
    }
}

struct ScrollCaptureView: NSViewRepresentable {
    let onScroll: (NSEvent) -> Void

    func makeNSView(context: Context) -> ScrollCaptureNSView {
        let v = ScrollCaptureNSView()
        v.onScroll = onScroll
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.clear.cgColor
        return v
    }

    func updateNSView(_ nsView: ScrollCaptureNSView, context: Context) {
        nsView.onScroll = onScroll
    }
}
