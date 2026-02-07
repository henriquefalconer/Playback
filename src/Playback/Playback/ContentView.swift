import SwiftUI
import AVKit
import AppKit

struct ContentView: View {
    @EnvironmentObject var timelineStore: TimelineStore
    @EnvironmentObject var playbackController: PlaybackController

    @State private var centerTime: TimeInterval = 0
    @State private var showDatePicker = false
    // Janela de tempo visível na timeline (em segundos).
    // 3600s = 1h visível ao redor do instante atual.
    @State private var visibleWindowSeconds: TimeInterval = 60 * 1
    // Limites de zoom: não permite dar zoom in/out além desses valores.
    private let minVisibleWindowSeconds: TimeInterval = 60          // 1 minuto
    private let maxVisibleWindowSeconds: TimeInterval = 60 * 60     // 60 minutos
    // Base usada para o gesto de pinça (zoom) aplicado na janela inteira.
    @State private var pinchBaseVisibleWindowSeconds: TimeInterval?
    // Exponente que controla a sensibilidade do zoom por pinça.
    // Valores maiores => zoom mais agressivo para a mesma distância de pinça.
    private let pinchZoomExponent: Double = 3.0
    @State private var keyMonitor: Any?
    @State private var scrollMonitor: Any?

    var body: some View {
        ZStack {
            VideoBackgroundView(player: playbackController.player)
                .ignoresSafeArea()

            // Enquanto um novo segmento está carregando (ou quando navegamos
            // para fora da faixa gravada), mostramos o último frame conhecido
            // como fallback para evitar "telas pretas" bruscas.
            // Para garantir que nenhuma outra imagem de fundo apareça ao redor
            // do frozen frame, renderizamos a imagem por cima de um fundo preto
            // que preenche toda a tela.
            if playbackController.showFrozenFrame, let image = playbackController.frozenFrame {
                ZStack {
                    Color.black
                        .ignoresSafeArea()

                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .ignoresSafeArea()
                }
            }

            // Gradiente inferior bem sutil em tons de cinza
            VStack {
                Spacer()
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color(.sRGB, red: 0.60, green: 0.68, blue: 0.98, opacity: 0.25) // cinza-azulado sutil
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 140)
                .ignoresSafeArea(edges: .bottom)
            }

            // Timeline + playhead + bubble
            GeometryReader { geo in
                VStack {
                    Spacer()

                    TimelineView(
                        centerTime: $centerTime,
                        visibleWindowSeconds: $visibleWindowSeconds,
                        showDatePicker: $showDatePicker
                    )
                    .environmentObject(timelineStore)
                    .environmentObject(playbackController)
                    .frame(height: 120)
                    .padding(.bottom, 40)
                    // Anima suavemente mudanças de zoom (visibleWindowSeconds),
                    // dando uma sensação de inércia ao gesto de pinça.
                    .animation(
                        .spring(response: 0.35, dampingFraction: 0.8, blendDuration: 0.15),
                        value: visibleWindowSeconds
                    )
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }

            if showDatePicker {
                DateTimePickerView(
                    isPresented: $showDatePicker,
                    selectedTime: Binding(
                        get: { playbackController.currentTime },
                        set: { newTime in
                            centerTime = newTime
                            playbackController.scrub(to: newTime)
                        }
                    )
                )
                .environmentObject(timelineStore)
                .transition(.opacity)
            }

        }
        .onAppear {
            // Se os segmentos já estiverem carregados quando a view aparecer,
            // posiciona imediatamente no instante mais recente.
            if let latest = timelineStore.latestTS {
                centerTime = latest
                playbackController.update(for: latest, store: timelineStore)
            }

            // Monitor de teclado para atalhos globais
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
                // keyCode 53 = ESC, 49 = Space, 123 = Left Arrow, 124 = Right Arrow
                switch event.keyCode {
                case 53:  // ESC - Close window
                    NSApp.keyWindow?.close()
                    return nil

                case 49:  // Space - Play/Pause
                    self.togglePlayPause()
                    return nil

                case 123:  // Left Arrow - Seek backward 5 seconds
                    let newTime = max(playbackController.currentTime - 5, timelineStore.timelineStart ?? 0)
                    playbackController.scrub(to: newTime)
                    centerTime = newTime
                    return nil

                case 124:  // Right Arrow - Seek forward 5 seconds
                    let newTime = min(playbackController.currentTime + 5, timelineStore.timelineEnd ?? playbackController.currentTime)
                    playbackController.scrub(to: newTime)
                    centerTime = newTime
                    return nil

                default:
                    return event
                }
            }
            // Monitor global de scroll para controlar o tempo do vídeo sem bloquear cliques
            // na timeline. Diferente do ScrollCaptureView anterior (que usava uma NSView
            // transparente por cima de tudo), este monitor apenas observa eventos de scroll,
            // sem interferir na hierarquia de hit-test da UI.
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                let rawDx = event.scrollingDeltaX
                let rawDy = event.scrollingDeltaY

                print("[ScrollCapture] event dx=\(rawDx), dy=\(rawDy), inverted=\(event.isDirectionInvertedFromDevice)")

                // Usamos o eixo de maior magnitude como direção principal do gesto.
                guard rawDx != 0 || rawDy != 0 else { return nil }
                let primaryRaw: CGFloat = abs(rawDx) >= abs(rawDy) ? rawDx : rawDy

                // Direção real do dedo (corrigida para "natural scrolling").
                let fingerDelta: CGFloat
                if event.isDirectionInvertedFromDevice {
                    fingerDelta = -primaryRaw
                } else {
                    fingerDelta = primaryRaw
                }

                print("[ScrollCapture] primaryRaw=\(primaryRaw), fingerDelta=\(fingerDelta)")

                // Fator de sensibilidade (ajuste fino da velocidade do scroll).
                // Em vez de um valor fixo muito pequeno (que praticamente não move a timeline),
                // escalamos pela janela visível: para uma janela de 1h, cada "ponto" de scroll
                // muda alguns segundos, o suficiente para perceber deslocamento contínuo.
                //
                // Exemplo: visibleWindowSeconds = 3600 -> ~3.6s por ponto.
                let secondsPerPoint: Double = visibleWindowSeconds / 1000.0

                // Regra de UX (invertida agora):
                //  - dedo/ponteiro para a DIREITA  => tempo MAIOR (futuro)
                //  - dedo/ponteiro para a ESQUERDA => tempo MENOR (passado)
                let secondsDelta = Double(fingerDelta) * secondsPerPoint

                guard secondsDelta != 0 else {
                    print("[ScrollCapture] secondsDelta == 0, ignorando")
                    return nil
                }

                // Baseamos o cálculo no currentTime do playbackController (sincronizado pelo timeObserver).
                let base = playbackController.currentTime
                var newTime = base + secondsDelta
                print("[ScrollCapture] baseTime=\(base), secondsDelta=\(secondsDelta), tentative newTime=\(newTime)")

                if let start = timelineStore.timelineStart {
                    newTime = max(start, newTime)
                }
                if let end = timelineStore.timelineEnd {
                    newTime = min(end, newTime)
                }

                print("[ScrollCapture] clamped newTime=\(newTime), timelineStart=\(String(describing: timelineStore.timelineStart)), timelineEnd=\(String(describing: timelineStore.timelineEnd))")

                // Atualiza estado da UI e faz scrubbing IMEDIATO (sem debounce),
                // mantendo o vídeo PAUSADO enquanto o usuário está scrollando.
                let beforeScrubCurrent = playbackController.currentTime
                print("[ScrollCapture] -> calling scrub(to: \(newTime)). currentTime(before)=\(beforeScrubCurrent), centerTime(before)=\(centerTime)")
                playbackController.scrub(to: newTime, store: timelineStore)
                // Após o scrub, sempre alinhamos o centerTime com o currentTime
                // efetivo do player (que pode ter sido "encaixado" no fim/início
                // de um segmento durante transições entre segmentos).
                centerTime = playbackController.currentTime
                print("[ScrollCapture] <- after scrub. playback.currentTime=\(playbackController.currentTime), centerTime=\(centerTime)")

                // Retornamos nil para evitar que alguma view padrão (ex: NSScrollView)
                // também processe esse scroll.
                return nil
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
                scrollMonitor = nil
            }
        }
        // Sempre que a contagem de segmentos mudar (carregamento inicial ou reload),
        // reposicionamos o centerTime para o último timestamp disponível.
        .onChange(of: timelineStore.segments.count) { _, newCount in
            guard newCount > 0, let latest = timelineStore.latestTS else { return }
            print("[ContentView] segments.count mudou para \(newCount); reposicionando centerTime em latestTS=\(latest)")
            centerTime = latest
            playbackController.update(for: latest, store: timelineStore)
        }
        // IMPORTANTE: durante o scrubbing via ScrollCapture/Timeline, quem controla
        // o player é o PlaybackController.scrub(...). Chamadas adicionais de
        // scheduleUpdate aqui podem brigar com o scrubbing e causar "saltos"
        // inesperados. Por isso, este hook fica temporariamente desativado.
        /*
        .onChange(of: centerTime) { _, newValue in
            print("[ContentView] centerTime mudou para \(newValue); chamando scheduleUpdate")
            playbackController.scheduleUpdate(for: newValue, store: timelineStore)
        }
        */
        // Permite zoom por pinça em QUALQUER área da janela, não apenas sobre a barra de segmentos.
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    guard value.isFinite, value > 0 else { return }

                    if pinchBaseVisibleWindowSeconds == nil {
                        pinchBaseVisibleWindowSeconds = visibleWindowSeconds
                    }
                    guard let base = pinchBaseVisibleWindowSeconds else { return }

                    // Aumentamos a sensibilidade do zoom aplicando um expoente
                    // sobre o valor da pinça. Assim, pequenos gestos geram
                    // mudanças mais perceptíveis na escala de tempo.
                    let factor = pow(Double(value), pinchZoomExponent)

                    // Zoom in => menor janela (menos segundos visíveis).
                    var newWindow = base / factor
                    if newWindow < minVisibleWindowSeconds {
                        newWindow = minVisibleWindowSeconds
                    } else if newWindow > maxVisibleWindowSeconds {
                        newWindow = maxVisibleWindowSeconds
                    }

                    if abs(newWindow - visibleWindowSeconds) > 0.001 {
                        visibleWindowSeconds = newWindow
                        print("[ContentView] Pinch zoom -> visibleWindowSeconds=\(visibleWindowSeconds)")
                    }
                }
                .onEnded { _ in
                    pinchBaseVisibleWindowSeconds = nil
                }
        )
    }

    private func togglePlayPause() {
        playbackController.togglePlayPause()
    }
}


