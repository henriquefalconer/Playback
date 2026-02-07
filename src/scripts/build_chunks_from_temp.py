#!/usr/bin/env python3
"""
Converte screenshots em `com.playback.Playback/temp/YYYYMM/DD` em vídeos
segmentados em `com.playback.Playback/chunks/YYYYMM/DD/<id>` (sem extensão),
inspirado no comportamento observado em `com.memoryvault.MemoryVault/chunks`.

Características principais deste script:
- Assume que os frames são PNGs salvos sem extensão pelo `record_screen.py`.
- Agrupa frames em segmentos de duração fixa (ex.: 5 segundos).
- Gera vídeos usando `ffmpeg` com codec HEVC (libx265), 30 fps, mantendo
  resolução original das imagens.
- Registra metadados básicos dos segmentos em um pequeno banco SQLite
  (`meta.sqlite3`) na raiz de `com.playback.Playback`.

Requisitos:
- ffmpeg instalado e disponível no PATH.
- Python 3.8+.
"""

import argparse
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import List, Optional, Tuple


PROJECT_ROOT = Path(__file__).resolve().parents[1]
PLAYBACK_ROOT = PROJECT_ROOT / "com.playback.Playback"
TEMP_ROOT = PLAYBACK_ROOT / "temp"
CHUNKS_ROOT = PLAYBACK_ROOT / "chunks"
META_DB_PATH = PLAYBACK_ROOT / "meta.sqlite3"


DATE_RE = re.compile(r"^(?P<date>\d{8})-(?P<time>\d{6})")


@dataclass
class FrameInfo:
    path: Path
    ts: float  # epoch seconds
    app_id: Optional[str]
    width: Optional[int] = None
    height: Optional[int] = None


def get_image_size(path: Path) -> Tuple[Optional[int], Optional[int]]:
    """
    Obtém (largura, altura) de um frame PNG usando ffprobe.
    Se algo falhar, retorna (None, None).
    """
    try:
        cmd = [
            "ffprobe",
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height",
            "-of",
            "csv=p=0:s=x",
            str(path),
        ]
        out = subprocess.check_output(cmd, text=True).strip()
        if not out:
            return None, None
        w_str, h_str = out.split("x")
        return int(w_str), int(h_str)
    except Exception:
        return None, None


def parse_timestamp_from_name(name: str) -> Optional[float]:
    """
    Tenta extrair timestamp do padrão YYYYMMDD-HHMMSS-... no nome do arquivo.
    Retorna epoch seconds ou None se não bater o padrão.
    """
    m = DATE_RE.match(name)
    if not m:
        return None
    date_str = m.group("date")
    time_str = m.group("time")
    dt = datetime.strptime(date_str + time_str, "%Y%m%d%H%M%S")
    return dt.timestamp()


def parse_app_from_name(name: str) -> Optional[str]:
    """
    Extrai o app_id do nome do frame, se estiver no formato:
      YYYYMMDD-HHMMSS-<uuid>-<app_id>
    Retorna None se não houver essa parte.
    """
    m = DATE_RE.match(name)
    if not m:
        return None
    # Após o match teremos algo como "-<uuid>-<app_id>"
    rest = name[m.end() :]
    if not rest.startswith("-"):
        return None
    rest = rest[1:]  # remove o primeiro '-'
    parts = rest.split("-", 1)
    if len(parts) != 2:
        return None
    # uuid = parts[0]
    app_id = parts[1] or None
    return app_id


def load_frames_for_day(day: str) -> List[FrameInfo]:
    """
    Carrega todos os frames de temp/YYYYMM/DD relativos ao dia informado
    como string YYYYMMDD.
    """
    year_month = day[:6]
    day_only = day[6:]
    day_dir = TEMP_ROOT / year_month / day_only

    if not day_dir.is_dir():
        raise FileNotFoundError(f"Pasta de frames não encontrada: {day_dir}")

    frames: List[FrameInfo] = []
    for entry in sorted(day_dir.iterdir()):
        if not entry.is_file():
            continue
        # Ignora arquivos ocultos/metadados (ex.: .DS_Store)
        if entry.name.startswith("."):
            continue

        # Para a linha do tempo, confiamos sempre no \"Date Created\" do arquivo
        # (st_birthtime no macOS). Se não existir, usamos mtime como fallback.
        st = entry.stat()
        ts = getattr(st, "st_birthtime", None) or st.st_mtime
        app_id = parse_app_from_name(entry.name)
        width, height = get_image_size(entry)

        # Se não conseguimos determinar largura/altura via ffprobe, este arquivo
        # provavelmente não é um PNG válido; melhor ignorar do que quebrar o ffmpeg.
        if width is None or height is None:
            print(f"[build_chunks] Ignorando arquivo não‑PNG ou inválido: {entry}")
            continue

        frames.append(
            FrameInfo(
                path=entry,
                ts=ts,
                app_id=app_id,
                width=width,
                height=height,
            )
        )

    frames.sort(key=lambda f: f.ts)
    return frames


def group_frames_by_count(
    frames: List[FrameInfo],
    max_frames_per_segment: int,
) -> List[List[FrameInfo]]:
    """
    Agrupa frames em segmentos contendo, no máximo, `max_frames_per_segment`
    frames consecutivos **e** garantindo que cada segmento tenha apenas um
    formato de quadro (mesma largura/altura).

    Isso \"comprime\" uma sequência arbitrariamente longa de screenshots em
    vídeos curtos de N frames (ex.: 150 frames = 5s a 30fps), sem repetir
    frames.
    """
    if max_frames_per_segment <= 0:
        return [frames] if frames else []

    segments: List[List[FrameInfo]] = []
    current_segment: List[FrameInfo] = []
    current_size: Optional[Tuple[Optional[int], Optional[int]]] = None

    for frame in frames:
        frame_size = (frame.width, frame.height)

        if not current_segment:
            current_segment = [frame]
            current_size = frame_size
            continue

        reached_max = len(current_segment) >= max_frames_per_segment
        # Se a resolução (largura/altura) mudar, sempre iniciamos um novo segmento,
        # mesmo que uma das medidas seja None. Isso garante que não misturamos
        # monitores diferentes no mesmo vídeo.
        size_changed = current_size is not None and frame_size != current_size

        if reached_max or size_changed:
            segments.append(current_segment)
            current_segment = [frame]
            current_size = frame_size
        else:
            current_segment.append(frame)

    if current_segment:
        segments.append(current_segment)

    return segments


def init_meta_db(path: Path) -> None:
    """
    Cria (se não existir) um pequeno banco SQLite para registrar segmentos
    de vídeo e faixas de uso por app (appsegments).
    """
    conn = sqlite3.connect(path)
    try:
        cur = conn.cursor()
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS segments (
                id TEXT PRIMARY KEY,
                date TEXT NOT NULL,
                start_ts REAL NOT NULL,
                end_ts REAL NOT NULL,
                frame_count INTEGER NOT NULL,
                fps REAL,
                width INTEGER,
                height INTEGER,
                file_size_bytes INTEGER NOT NULL,
                video_path TEXT NOT NULL
            )
            """
        )
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS appsegments (
                id TEXT PRIMARY KEY,
                app_id TEXT,
                date TEXT NOT NULL,
                start_ts REAL NOT NULL,
                end_ts REAL NOT NULL
            )
            """
        )
        conn.commit()
    finally:
        conn.close()


def generate_segment_id() -> str:
    """
    Gera um ID curto pseudo-aleatório para o segmento.
    Não precisa bater exatamente o padrão do app original.
    """
    return os.urandom(10).hex()


def run_ffmpeg_make_segment(
    frames: List[FrameInfo],
    fps: float,
    crf: int,
    preset: str,
    dest_without_ext: Path,
) -> Tuple[int, Optional[int], Optional[int]]:
    """
    Gera um vídeo HEVC a partir de uma lista de frames, usando ffmpeg.
    Retorna (file_size_bytes, width, height).
    """
    # Arquivo final usará extensão .mp4 para melhor compatibilidade com AVPlayer/QuickTime.
    dest_tmp = dest_without_ext.with_suffix(".mp4")

    with tempfile.TemporaryDirectory() as tmpdir_str:
        tmpdir = Path(tmpdir_str)

        # Copia frames para nomes sequenciais .png
        for idx, frame in enumerate(frames, start=1):
            target = tmpdir / f"frame_{idx:05d}.png"
            shutil.copy2(frame.path, target)

        cmd = [
            "ffmpeg",
            "-y",
            "-framerate",
            str(fps),
            "-i",
            str(tmpdir / "frame_%05d.png"),
            "-c:v",
            "libx264",  # H.264 para melhor compatibilidade com AVPlayer/QuickTime
            "-preset",
            preset,
            "-crf",
            str(crf),
            "-pix_fmt",
            "yuv420p",
            str(dest_tmp),
        ]

        subprocess.run(cmd, check=True)

    # Mantemos a extensão .mp4 (não renomeamos), pois players nativos do macOS
    # se baseiam bastante na extensão para detectar o formato.
    st = dest_tmp.stat()
    size = st.st_size

    # Pega width/height com ffprobe (opcional)
    try:
        probe_cmd = [
            "ffprobe",
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(dest_tmp),
        ]
        out = subprocess.check_output(probe_cmd, text=True)
        lines = [l for l in out.splitlines() if l.strip()]
        if len(lines) >= 2:
            width = int(lines[0])
            height = int(lines[1])
        else:
            width = height = None
    except Exception:
        width = height = None

    return size, width, height


def insert_segment_meta(
    db_path: Path,
    segment_id: str,
    date_str: str,
    frames: List[FrameInfo],
    fps: float,
    file_size_bytes: int,
    video_rel_path: str,
    width: Optional[int],
    height: Optional[int],
) -> None:
    conn = sqlite3.connect(db_path)
    try:
        cur = conn.cursor()
        # Usamos timestamps reais dos frames (Date Created em temp) para
        # representar o intervalo coberto por este segmento.
        start_ts = frames[0].ts
        end_ts = frames[-1].ts
        cur.execute(
            """
            INSERT OR REPLACE INTO segments
            (id, date, start_ts, end_ts, frame_count, fps, width, height, file_size_bytes, video_path)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                segment_id,
                date_str,
                start_ts,
                end_ts,
                len(frames),
                fps,
                width,
                height,
                file_size_bytes,
                video_rel_path,
            ),
        )
        conn.commit()
    finally:
        conn.close()


def insert_appsegment_meta(
    db_path: Path,
    appsegment_id: str,
    date_str: str,
    app_id: Optional[str],
    start_ts: float,
    end_ts: float,
) -> None:
    """
    Registra uma faixa contínua de tempo em que um determinado app (app_id)
    estava ativo na tela. Essas faixas podem atravessar múltiplos segmentos
    de vídeo ou cobrir apenas parte de um segmento.
    """
    conn = sqlite3.connect(db_path)
    try:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT OR REPLACE INTO appsegments
            (id, app_id, date, start_ts, end_ts)
            VALUES (?, ?, ?, ?, ?)
            """,
            (appsegment_id, app_id, date_str, start_ts, end_ts),
        )
        conn.commit()
    finally:
        conn.close()


def build_appsegments_for_day(frames: List[FrameInfo]) -> List[Tuple[Optional[str], float, float]]:
    """
    A partir de todos os frames de um dia (já ordenados por timestamp),
    agrupa intervals contínuos por app_id.

    - Cada mudança de app_id inicia um novo appsegment.
    - app_id pode ser None; nesses casos ainda criamos um appsegment para
      representar períodos "sem app conhecido", que podem ser exibidos
      com uma cor genérica na timeline.
    """
    if not frames:
        return []

    segments: List[Tuple[Optional[str], float, float]] = []

    current_app: Optional[str] = frames[0].app_id
    current_start: float = frames[0].ts
    last_ts: float = frames[0].ts

    for frame in frames[1:]:
        if frame.app_id == current_app:
            # Continua o mesmo app; apenas avança o fim do intervalo.
            last_ts = frame.ts
            continue

        # Houve troca de app: fecha o intervalo atual em last_ts
        segments.append((current_app, current_start, last_ts))

        # Inicia um novo intervalo para o novo app.
        current_app = frame.app_id
        current_start = frame.ts
        last_ts = frame.ts

    # Fecha o último intervalo usando o timestamp do último frame.
    segments.append((current_app, current_start, last_ts))

    return segments


def process_day(
    day: str,
    fps: float,
    segment_duration: float,
    crf: int,
    preset: str,
) -> None:
    """
    Gera vídeos a partir dos frames de um dia (YYYYMMDD).
    """
    frames = load_frames_for_day(day)
    if not frames:
        print(f"[build_chunks] Nenhum frame encontrado para o dia {day}")
        return

    # Faixas de app (appsegments) para o dia inteiro, independentes de como
    # os frames serão agrupados em vídeos (segments).
    appsegments = build_appsegments_for_day(frames)

    # Número alvo de frames por segmento: fps * duração desejada em segundos.
    max_frames_per_segment = int(fps * segment_duration)
    segments = group_frames_by_count(frames, max_frames_per_segment)
    print(f"[build_chunks] Dia {day}: {len(frames)} frames em {len(segments)} segmentos")

    year_month = day[:6]
    day_only = day[6:]
    day_chunks_dir = CHUNKS_ROOT / year_month / day_only
    day_chunks_dir.mkdir(parents=True, exist_ok=True)

    init_meta_db(META_DB_PATH)

    date_str = f"{day[:4]}-{day[4:6]}-{day[6:]}"

    for idx, seg_frames in enumerate(segments, start=1):
        segment_id = generate_segment_id()
        dest_without_ext = day_chunks_dir / segment_id
        print(f"[build_chunks] Segmento {idx}/{len(segments)} -> {dest_without_ext}.mp4")

        size, width, height = run_ffmpeg_make_segment(
            seg_frames,
            fps=fps,
            crf=crf,
            preset=preset,
            dest_without_ext=dest_without_ext,
        )

        # Caminho relativo deve apontar para o arquivo .mp4
        rel_path = str(dest_without_ext.with_suffix(".mp4").relative_to(PLAYBACK_ROOT))
        insert_segment_meta(
            META_DB_PATH,
            segment_id=segment_id,
            date_str=date_str,
            frames=seg_frames,
            fps=fps,
            file_size_bytes=size,
            video_rel_path=rel_path,
            width=width,
            height=height,
        )

    # Persiste todos os appsegments calculados para o dia.
    for app_id, start_ts, end_ts in appsegments:
        appsegment_id = generate_segment_id()
        insert_appsegment_meta(
            META_DB_PATH,
            appsegment_id=appsegment_id,
            date_str=date_str,
            app_id=app_id,
            start_ts=start_ts,
            end_ts=end_ts,
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Converte screenshots em temp/YYYYMM/DD em vídeos em chunks/YYYYMM/DD"
    )
    parser.add_argument(
        "--day",
        type=str,
        required=True,
        help="Dia no formato YYYYMMDD (ex.: 20251222)",
    )
    parser.add_argument(
        "--fps",
        type=float,
        default=30.0,
        help="FPS do vídeo de saída (default: 30.0)",
    )
    parser.add_argument(
        "--segment-duration",
        type=float,
        default=5.0,
        help="Duração alvo de cada segmento em segundos (default: 5.0)",
    )
    parser.add_argument(
        "--crf",
        type=int,
        default=28,
        help="CRF do libx265 (quanto maior, mais compressão; default: 28)",
    )
    parser.add_argument(
        "--preset",
        type=str,
        default="veryfast",
        help="Preset do libx265 (default: veryfast)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    process_day(
        day=args.day,
        fps=args.fps,
        segment_duration=args.segment_duration,
        crf=args.crf,
        preset=args.preset,
    )


if __name__ == "__main__":
    main()


