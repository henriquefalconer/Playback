import Foundation
import AVFoundation
import Combine
import AppKit

final class PlaybackController: ObservableObject {
    let player = AVPlayer()

    @Published private(set) var currentSegment: Segment?
    @Published var currentTime: TimeInterval = 0
    @Published var isPlaying: Bool = false
    /// Último frame "congelado" usado como fallback visual enquanto um novo
    /// segmento é carregado ou quando navegamos para fora da faixa gravada.
    @Published var frozenFrame: NSImage?
    /// Quando `true`, a UI deve exibir `frozenFrame` por cima do vídeo.
    @Published var showFrozenFrame: Bool = false

    /// Indica se estamos no meio de um scrubbing ativo (via scroll/drag).
    /// Enquanto for `true`, ignoramos as atualizações periódicas do `timeObserver`
    /// para não sobrescrever o `currentTime` calculado a partir do gesto.
    private var isScrubbing: Bool = false
    /// Indica se o tempo atual está "grudado" no início absoluto da timeline.
    /// Quando verdadeiro, mantemos o último frame exibido como fallback
    /// visual, mesmo após o fim do scrubbing.
    private var atStartBoundary: Bool = false

    private var timeObserverToken: Any?

    private var pendingWorkItem: DispatchWorkItem?
    private var statusObserver: NSKeyValueObservation?
    private var scrubEndWorkItem: DispatchWorkItem?

    init() {
        // Observa periodicamente o tempo do player para manter `currentTime`
        // sempre em sincronia com o que está sendo exibido na tela,
        // inclusive quando o usuário faz scroll/gestos diretamente no vídeo.
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] cmTime in
            guard let self = self else { return }
            // Durante scrubbing, NÃO deixamos o player "puxar" o currentTime
            // de volta para o tempo de vídeo real, pois isso causa saltos
            // perceptíveis na timeline entre eventos de scroll.
            if self.isScrubbing { return }
            guard let segment = self.currentSegment else { return }

            let seconds = CMTimeGetSeconds(cmTime)
            guard seconds.isFinite, seconds >= 0 else { return }

            // Em vez de assumir mapeamento 1:1 (startTS + seconds), usamos o
            // inverso da função `videoOffset(forAbsoluteTime:)` para voltar do
            // tempo do vídeo para o tempo absoluto da timeline. Isso evita
            // "teletransportes" para o início do segmento quando estamos no
            // meio dele.
            self.currentTime = segment.absoluteTime(forVideoOffset: seconds)
        }
    }

    /// Gera, em background, um snapshot do vídeo para o `segment` na posição
    /// correspondente ao tempo absoluto dado, e publica em `frozenFrame`.
    private func captureFrozenFrame(from segment: Segment, atAbsoluteTime time: TimeInterval) {
        let offset = max(0, segment.videoOffset(forAbsoluteTime: time))
        let url = segment.videoURL

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true

            let cmTime = CMTime(seconds: offset, preferredTimescale: 600)
            generator.generateCGImageAsynchronously(for: cmTime) { [weak self] image, _, error in
                guard let self else { return }

                if let cgImage = image {
                    let nsImage = NSImage(cgImage: cgImage, size: .zero)
                    DispatchQueue.main.async {
                        self.frozenFrame = nsImage
                        self.showFrozenFrame = true
                    }
                } else if let error = error {
                    let message = error.localizedDescription
                    print("[Playback] Falha ao gerar frozen frame (async) para \(url.path) em offset=\(offset): \(message)")
                } else {
                    print("[Playback] Geração de frozen frame (async) não retornou imagem nem erro para \(url.path) em offset=\(offset)")
                }
            }
        }
    }

    deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
    }

    /// Atualiza o player para um determinado tempo **sem iniciar a reprodução**.
    /// Usado para scrubbing em tempo real (ex.: gesto de scroll/drag na timeline),
    /// deixando o frame sempre sincronizado com a posição atual, mas em pausa.
    func scrub(to time: TimeInterval, store: TimelineStore) {
        // Marca que estamos em scrubbing ativo.
        isScrubbing = true
        scrubEndWorkItem?.cancel()

        let segments = store.segments
        guard let first = segments.first, let last = segments.last else {
            print("[Playback] (scrub) Nenhum segmento disponível (lista vazia)")
            isScrubbing = false
            return
        }

        // Clampeia o tempo pedido para dentro do range global da timeline.
        var clampedTime = min(max(time, first.startTS), last.endTS)

        // Detecta se estamos exatamente encostados no início absoluto da timeline.
        // Nessa condição, queremos manter o último frame exibido como fallback
        // visual, já que não existe vídeo "antes" do primeiro segmento.
        let nowAtStartBoundary = abs(clampedTime - first.startTS) < 0.001
        if nowAtStartBoundary {
            // Garante que temos um frame congelado para mostrar. Se ainda não
            // houver um, usamos o frame do segmento atual (se existir).
            if frozenFrame == nil || !atStartBoundary, let seg = currentSegment {
                captureFrozenFrame(from: seg, atAbsoluteTime: currentTime)
            }
            showFrozenFrame = true
        }
        atStartBoundary = nowAtStartBoundary

        // --- Correção 1: "grudar" levemente nas bordas do segmento atual ---
        // Quando o usuário está exatamente no começo/fim de um segmento e faz um
        // scroll MUITO pequeno para o passado/futuro, não queremos pular
        // imediatamente para o segmento anterior/seguinte (especialmente se
        // existir um "buraco" grande entre eles).
        //
        // Em vez disso, mantemos o tempo "preso" na borda atual enquanto o
        // deslocamento for pequeno, e só permitimos atravessar a borda quando o
        // usuário insistir um pouco mais.
        if let seg = currentSegment {
            let boundaryStick: TimeInterval = 0.5   // até 0.5s além da borda continua preso

            if clampedTime < seg.startTS {
                let delta = seg.startTS - clampedTime
                if delta <= boundaryStick {
                    clampedTime = seg.startTS
                }
            } else if clampedTime > seg.endTS {
                let delta = clampedTime - seg.endTS
                if delta <= boundaryStick {
                    clampedTime = seg.endTS
                }
            }
        }

        let direction = clampedTime - currentTime

        // Caso padrão: usa o mapeamento canônico do TimelineStore, que já trata:
        //  - tempo dentro de segmento
        //  - buracos entre segmentos (considerando direção)
        //  - antes do primeiro / depois do último segmento
        guard let (seg, offset) = store.segment(for: clampedTime, direction: direction) else {
            print("[Playback] (scrub) segment(for: \(clampedTime), dir=\(direction)) retornou nil")
            return
        }

        // Atualiza o tempo absoluto atual na timeline (coordenada contínua).
        currentTime = clampedTime

        print("[Playback] (scrub) time=\(time), clamped=\(clampedTime), effectiveTime=\(clampedTime), direction=\(direction)")

        let distToStart = clampedTime - seg.startTS
        let distToEnd = seg.endTS - clampedTime

        print(
            "[Playback] (scrub) usando segment(for:): id=\(seg.id), " +
            "videoOffset=\(offset), " +
            "distToStart=\(distToStart), distToEnd=\(distToEnd)"
        )
        seek(to: seg, offset: offset, isScrub: true)

        // Agenda o fim do scrubbing um pouco após o último evento de scroll.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isScrubbing = false
            // Ao terminar o scrubbing, se o player já tiver um novo frame
            // válido pronto (status READY) e **não** estivermos encostados
            // no início absoluto da timeline, podemos esconder o congelado.
            if !self.atStartBoundary {
                self.showFrozenFrame = false
            }
        }
        scrubEndWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func play() {
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    private func seek(to segment: Segment, offset: TimeInterval, isScrub: Bool) {
        // Se mudou de segmento, trocamos o item do player.
        if currentSegment?.id != segment.id {
            if let oldSeg = currentSegment {
                // Antes de trocar de segmento, congelamos o último frame para
                // evitar o "flash" preto enquanto o novo vídeo carrega.
                captureFrozenFrame(from: oldSeg, atAbsoluteTime: currentTime)
            }

            currentSegment = segment
            let url = segment.videoURL
            let item = AVPlayerItem(url: url)

            // Mantemos o observer de status para debug se algo der errado no carregamento.
            statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    print("[Playback] \(isScrub ? "(scrub) " : "")READY to play \(url.path)")
                    DispatchQueue.main.async {
                        // Só escondemos o frame congelado se não estivermos
                        // mais em scrubbing. Durante scrubbing, mantemos o
                        // último frame exibido para evitar flashes pretos
                        // mesmo que o novo segmento já esteja pronto.
                        if !self.isScrubbing {
                            self.showFrozenFrame = false
                        }
                    }
                case .failed:
                    print("[Playback] \(isScrub ? "(scrub) " : "")FAILED for \(url.path): \(item.error?.localizedDescription ?? "(sem erro)")")
                    DispatchQueue.main.async {
                        if !self.isScrubbing {
                            self.showFrozenFrame = false
                        }
                    }
                case .unknown:
                    print("[Playback] \(isScrub ? "(scrub) " : "")status UNKNOWN para \(url.path)")
                @unknown default:
                    print("[Playback] \(isScrub ? "(scrub) " : "")status desconhecido para \(url.path)")
                }
            }

            player.replaceCurrentItem(with: item)
        }

        let cm = CMTime(seconds: offset, preferredTimescale: 600)
        if isScrub {
            // Pausa sempre durante o scrubbing para evitar sensação "elástica".
            player.pause()
            player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    func update(for time: TimeInterval, store: TimelineStore) {
        guard let (segment, offset) = store.segment(for: time) else {
            print("[Playback] Nenhum segmento encontrado para time=\(time)")
            return
        }
        print("[Playback] Atualizando para segmento \(segment.id) (videoOffset=\(offset))")
        print("          URL: \(segment.videoURL.path)")
        print("          exists: \(FileManager.default.fileExists(atPath: segment.videoURL.path))")
        currentTime = time

        if currentSegment?.id != segment.id {
            if let oldSeg = currentSegment {
                // Congela o último frame do segmento anterior antes de trocar.
                captureFrozenFrame(from: oldSeg, atAbsoluteTime: currentTime)
            }

            let url = segment.videoURL
            let item = AVPlayerItem(url: url)

            currentSegment = segment

            // Observar status para entender falhas de decodificação/carregamento
            statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    print("[Playback] READY to play \(url.path)")
                    DispatchQueue.main.async {
                        if !self.isScrubbing {
                            self.showFrozenFrame = false
                        }
                    }
                case .failed:
                    print("[Playback] FAILED for \(url.path): \(item.error?.localizedDescription ?? "(sem erro)")")
                    DispatchQueue.main.async {
                        if !self.isScrubbing {
                            self.showFrozenFrame = false
                        }
                    }
                case .unknown:
                    print("[Playback] status UNKNOWN para \(url.path)")
                @unknown default:
                    print("[Playback] status desconhecido para \(url.path)")
                }
            }

            player.replaceCurrentItem(with: item)
            let cm = CMTime(seconds: offset, preferredTimescale: 600)
            player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                self?.player.play()
            }
        } else {
            let cm = CMTime(seconds: offset, preferredTimescale: 600)
            player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    func scheduleUpdate(for time: TimeInterval, store: TimelineStore) {
        pendingWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                self?.update(for: time, store: store)
            }
        }
        pendingWorkItem = work
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2, execute: work)
    }
}


