import Foundation
import Combine
import SQLite3

struct Segment: Identifiable {
    let id: String
    let startTS: TimeInterval
    let endTS: TimeInterval
    let frameCount: Int
    let fps: Double?
    let videoURL: URL

    var duration: TimeInterval {
        max(0, endTS - startTS)
    }

    /// Duração real do vídeo (em segundos), estimada a partir de frameCount e fps.
    var videoDuration: TimeInterval? {
        guard let fps, fps > 0, frameCount > 0 else { return nil }
        return TimeInterval(Double(frameCount) / fps)
    }

    /// Converte um timestamp absoluto (linha do tempo global) em offset dentro do
    /// arquivo de vídeo correspondente a este segmento.
    func videoOffset(forAbsoluteTime time: TimeInterval) -> TimeInterval {
        let clampedTime = min(max(time, startTS), endTS)
        let timelineOffset = max(0, min(clampedTime - startTS, duration))

        guard let videoDuration, duration > 0 else {
            return timelineOffset
        }

        // Mapeamento linear simples: todo o intervalo da timeline deste segmento
        // [startTS, endTS] percorre 100% da duração do vídeo [0, videoDuration].
        // Isso evita "travamento" do vídeo no início ou fim do segmento e garante
        // scrubbing contínuo ao longo de todo o segmento.
        let ratio = timelineOffset / duration
        if !ratio.isFinite || ratio < 0 {
            return 0
        }
        let mapped = videoDuration * min(1.0, ratio)
        return max(0, min(videoDuration, mapped))
    }

    /// Inverso aproximado de `videoOffset(forAbsoluteTime:)`.
    /// Dado um offset dentro do vídeo (em segundos), devolve o timestamp absoluto
    /// correspondente na linha do tempo global.
    ///
    /// Isso garante que, quando o AVPlayer reporta o tempo corrente do vídeo,
    /// consigamos mapeá‑lo de volta para o tempo "real" da timeline sem causar
    /// saltos inesperados para o início do segmento.
    func absoluteTime(forVideoOffset offset: TimeInterval) -> TimeInterval {
        let clampedOffset = max(0, offset)

        guard let videoDuration, videoDuration > 0, duration > 0 else {
            // Sem metadados confiáveis: assumimos mapeamento 1:1 local ao segmento.
            let local = min(clampedOffset, duration)
            return startTS + local
        }

        let ratio = min(max(clampedOffset / videoDuration, 0), 1)
        let timelineOffset = ratio * duration
        return startTS + timelineOffset
    }
}

struct AppSegment: Identifiable {
    let id: String
    let startTS: TimeInterval
    let endTS: TimeInterval
    let appId: String?

    var duration: TimeInterval {
        max(0, endTS - startTS)
    }
}

final class TimelineStore: ObservableObject {
    @Published private(set) var segments: [Segment] = []
    @Published private(set) var appSegments: [AppSegment] = []

    var timelineStart: TimeInterval? {
        segments.first?.startTS
    }

    var timelineEnd: TimeInterval? {
        segments.last?.endTS
    }

    var latestTS: TimeInterval? {
        timelineEnd
    }

    private let dbPath: String
    private let baseDir: URL
    private var refreshTimer: Timer?

    init() {
        // Use environment-aware paths from Paths utility
        self.baseDir = Paths.baseDataDirectory
        self.dbPath = Paths.databasePath.path

        // Ensure directories exist before loading data
        do {
            try Paths.ensureDirectoriesExist()
        } catch {
            print("[TimelineStore] Error creating directories: \(error)")
        }

        loadSegments()
        startAutoRefresh()
    }

    init(dbPath: String, baseDir: URL, autoRefresh: Bool = true) {
        self.dbPath = dbPath
        self.baseDir = baseDir

        loadSegments()
        if autoRefresh {
            startAutoRefresh()
        }
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshIfNeeded()
        }
    }

    private func refreshIfNeeded() {
        let previousCount = segments.count
        loadSegments()
        if segments.count != previousCount {
            print("[TimelineStore] Auto-refreshed: \(segments.count) segments (was \(previousCount))")
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    private func loadSegments() {
        var db: OpaquePointer?
        let rc = sqlite3_open(dbPath, &db)
        guard rc == SQLITE_OK, let db else {
            let errorMessage: String
            if let db {
                errorMessage = String(cString: sqlite3_errmsg(db))
                sqlite3_close(db)
            } else {
                errorMessage = "sqlite3_open returned code \(rc) e db == nil"
            }
            print("[TimelineStore] Não foi possível abrir meta.sqlite3 em \(dbPath). rc=\(rc), erro=\(errorMessage)")
            return
        }
        defer { sqlite3_close(db) }

        let query = """
        SELECT id, start_ts, end_ts, frame_count, fps, video_path
        FROM segments
        ORDER BY start_ts ASC;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            print("[TimelineStore] Erro ao preparar query segments")
            return
        }
        defer { sqlite3_finalize(stmt) }

        var loaded: [Segment] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let idC = sqlite3_column_text(stmt, 0),
                let videoPathC = sqlite3_column_text(stmt, 5)
            else { continue }

            let id = String(cString: idC)
            let startTS = sqlite3_column_double(stmt, 1)
            let endTS = sqlite3_column_double(stmt, 2)
            let frameCount = Int(sqlite3_column_int(stmt, 3))
            let fpsValue = sqlite3_column_double(stmt, 4)
            let fps: Double? = fpsValue > 0 ? fpsValue : nil
            let videoPath = String(cString: videoPathC)

            let url = baseDir.appendingPathComponent(videoPath)
            loaded.append(
                Segment(
                    id: id,
                    startTS: startTS,
                    endTS: endTS,
                    frameCount: frameCount,
                    fps: fps,
                    videoURL: url
                )
            )
        }

        // Carrega também os appsegments, se a tabela existir.
        let appQuery = """
        SELECT id, app_id, start_ts, end_ts
        FROM appsegments
        ORDER BY start_ts ASC;
        """

        var appStmt: OpaquePointer?
        var loadedAppSegments: [AppSegment] = []

        if sqlite3_prepare_v2(db, appQuery, -1, &appStmt, nil) == SQLITE_OK, let appStmt {
            defer { sqlite3_finalize(appStmt) }

            while sqlite3_step(appStmt) == SQLITE_ROW {
                guard let idC = sqlite3_column_text(appStmt, 0) else { continue }
                let id = String(cString: idC)

                let appId: String?
                if let appIdC = sqlite3_column_text(appStmt, 1) {
                    appId = String(cString: appIdC)
                } else {
                    appId = nil
                }

                let startTS = sqlite3_column_double(appStmt, 2)
                let endTS = sqlite3_column_double(appStmt, 3)

                loadedAppSegments.append(
                    AppSegment(
                        id: id,
                        startTS: startTS,
                        endTS: endTS,
                        appId: appId
                    )
                )
            }
        } else {
            print("[TimelineStore] Tabela appsegments não encontrada ou erro ao preparar query; apenas segments serão carregados.")
        }

        DispatchQueue.main.async {
            self.segments = loaded
            self.appSegments = loadedAppSegments
            print("[TimelineStore] Carregados \(loaded.count) segments e \(loadedAppSegments.count) appsegments")
        }
    }

    /// Versão simples (sem direção explícita) usada em pontos onde não estamos
    /// fazendo scrubbing contínuo. Nesses casos, a regra de "segmento mais
    /// próximo" é suficiente.
    func segment(for time: TimeInterval) -> (Segment, TimeInterval)? {
        segment(for: time, direction: 0)
    }

    /// Versão estendida que recebe também a direção do movimento:
    ///  - direction > 0  -> indo para o FUTURO
    ///  - direction < 0  -> indo para o PASSADO
    ///  - direction == 0 -> sem direção clara (ex: chamada isolada)
    ///
    /// Isso permite tratar corretamente os "buracos" entre segmentos sem
    /// causar saltos inesperados.
    func segment(for time: TimeInterval, direction: TimeInterval) -> (Segment, TimeInterval)? {
        guard !segments.isEmpty else { return nil }

        let dirSign: Int
        if direction > 0 {
            dirSign = 1
        } else if direction < 0 {
            dirSign = -1
        } else {
            dirSign = 0
        }

        // 1) Fora da faixa global (antes do primeiro ou depois do último)?
        if let first = segments.first, time < first.startTS {
            let offset = first.videoOffset(forAbsoluteTime: first.startTS)
            print("[TimelineStore] segment(for:\(time), dir=\(direction)) -> antes do primeiro, usando \(first.id) @ start, videoOffset=\(offset)")
            return (first, offset)
        }
        if let last = segments.last, time > last.endTS {
            let offset = last.videoOffset(forAbsoluteTime: last.endTS)
            print("[TimelineStore] segment(for:\(time), dir=\(direction)) -> depois do último, usando \(last.id) @ end, videoOffset=\(offset)")
            return (last, offset)
        }

        // 2) Dentro de algum segmento?
        for seg in segments {
            if time >= seg.startTS && time <= seg.endTS {
                let offset = seg.videoOffset(forAbsoluteTime: time)
                print("[TimelineStore] segment(for:\(time), dir=\(direction)) -> dentro de \(seg.id), videoOffset=\(offset)")
                return (seg, offset)
            }
        }

        // 3) Entre segmentos (em "buracos").
        // Detecta explicitamente o par (anterior, próximo) cujo gap contém `time`.
        if segments.count >= 2 {
            for i in 0..<(segments.count - 1) {
                let a = segments[i]
                let b = segments[i + 1]

                if time > a.endTS && time < b.startTS {
                    if dirSign < 0 {
                        // Indo para o PASSADO: usamos o FIM do segmento anterior.
                        let offset = a.videoOffset(forAbsoluteTime: a.endTS)
                        print("[TimelineStore] segment(for:\(time), dir=\(direction)) -> buraco, PASSADO: usando fim de \(a.id), videoOffset=\(offset)")
                        return (a, offset)
                    } else if dirSign > 0 {
                        // Indo para o FUTURO: usamos o INÍCIO do próximo segmento.
                        let offset = b.videoOffset(forAbsoluteTime: b.startTS)
                        print("[TimelineStore] segment(for:\(time), dir=\(direction)) -> buraco, FUTURO: usando início de \(b.id), videoOffset=\(offset)")
                        return (b, offset)
                    } else {
                        // Sem direção clara (ex: chamada isolada): mantém a regra antiga
                        // de "segmento mais próximo".
                        let distA = min(abs(time - a.startTS), abs(time - a.endTS))
                        let distB = min(abs(time - b.startTS), abs(time - b.endTS))
                        let chosen = distA <= distB ? a : b
                        let clamped = min(max(time, chosen.startTS), chosen.endTS)
                        let offset = chosen.videoOffset(forAbsoluteTime: clamped)
                        print("[TimelineStore] segment(for:\(time), dir=\(direction)) -> buraco, SEM DIREÇÃO: usando \(chosen.id), videoOffset=\(offset)")
                        return (chosen, offset)
                    }
                }
            }
        }

        // 4) Fallback de segurança: escolhe o segmento mais próximo.
        var bestSeg: Segment?
        var bestOffset: TimeInterval = 0
        var bestDistance = TimeInterval.greatestFiniteMagnitude

        for seg in segments {
            let clamped = min(max(time, seg.startTS), seg.endTS)
            let distance = abs(time - clamped)
            if distance < bestDistance {
                bestDistance = distance
                bestSeg = seg
                bestOffset = seg.videoOffset(forAbsoluteTime: clamped)
            }
        }

        if let seg = bestSeg {
            print("[TimelineStore] segment(for:\(time), dir=\(direction)) -> fallback, usando \(seg.id), videoOffset=\(bestOffset)")
            return (seg, bestOffset)
        }
        print("[TimelineStore] segment(for:\(time), dir=\(direction)) -> nenhum segmento encontrado (CASO INESPERADO)")
        return nil
    }
}

