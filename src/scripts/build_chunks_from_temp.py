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
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Tuple

# Add parent directory to path for lib imports
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lib.database import init_database, generate_segment_id
from lib.paths import get_temp_directory, get_chunks_directory, get_database_path
from lib.timestamps import parse_timestamp_from_name, parse_app_from_name
from lib.video import get_image_size, create_video_from_images


@dataclass
class FrameInfo:
    path: Path
    ts: float  # epoch seconds
    app_id: Optional[str]
    width: Optional[int] = None
    height: Optional[int] = None


def load_frames_for_day(day: str) -> List[FrameInfo]:
    """
    Carrega todos os frames de temp/YYYYMM/DD relativos ao dia informado
    como string YYYYMMDD.
    """
    year_month = day[:6]
    day_only = day[6:]
    day_dir = get_temp_directory() / year_month / day_only

    if not day_dir.is_dir():
        raise FileNotFoundError(f"Pasta de frames não encontrada: {day_dir}")

    frames: List[FrameInfo] = []
    for entry in sorted(day_dir.iterdir()):
        if not entry.is_file():
            continue
        # Ignora arquivos ocultos/metadados (ex.: .DS_Store)
        if entry.name.startswith("."):
            continue

        # Para a linha do tempo, confiamos sempre no "Date Created" do arquivo
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

    Isso "comprime" uma sequência arbitrariamente longa de screenshots em
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


def cleanup_temp_files(frames: List[FrameInfo], day: str) -> None:
    """
    Remove os arquivos temporários (screenshots) após processamento bem-sucedido.

    Args:
        frames: Lista de frames que foram processados com sucesso
        day: String YYYYMMDD representando o dia processado
    """
    print(f"[build_chunks] Limpando {len(frames)} arquivos temporários...")

    deleted_count = 0
    error_count = 0

    for frame in frames:
        try:
            if frame.path.exists():
                frame.path.unlink()
                deleted_count += 1
        except Exception as e:
            print(f"[build_chunks] AVISO: Não foi possível deletar {frame.path}: {e}")
            error_count += 1

    print(f"[build_chunks] Limpeza concluída: {deleted_count} arquivos deletados, {error_count} erros")

    # Tenta remover o diretório do dia se estiver vazio
    try:
        year_month = day[:6]
        day_only = day[6:]
        day_dir = get_temp_directory() / year_month / day_only

        # Verifica se o diretório está vazio (ignora .DS_Store e outros arquivos ocultos)
        remaining_files = [f for f in day_dir.iterdir() if not f.name.startswith('.')]

        if not remaining_files:
            day_dir.rmdir()
            print(f"[build_chunks] Diretório temporário vazio removido: {day_dir}")

            # Tenta remover o diretório do mês se também estiver vazio
            month_dir = day_dir.parent
            if not any(month_dir.iterdir()):
                month_dir.rmdir()
                print(f"[build_chunks] Diretório do mês vazio removido: {month_dir}")
    except Exception as e:
        print(f"[build_chunks] AVISO: Não foi possível remover diretórios vazios: {e}")


def process_day(
    day: str,
    fps: float,
    segment_duration: float,
    crf: int,
    preset: str,
    cleanup: bool = True,
) -> None:
    """
    Gera vídeos a partir dos frames de um dia (YYYYMMDD).

    Args:
        day: Dia no formato YYYYMMDD
        fps: Frames por segundo do vídeo de saída
        segment_duration: Duração de cada segmento em segundos
        crf: Constant Rate Factor para compressão
        preset: Preset do FFmpeg (veryfast, medium, slow, etc.)
        cleanup: Se True, remove os arquivos temporários após processamento
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
    day_chunks_dir = get_chunks_directory() / year_month / day_only
    day_chunks_dir.mkdir(parents=True, exist_ok=True)

    db = init_database(get_database_path())

    date_str = f"{day[:4]}-{day[4:6]}-{day[6:]}"

    for idx, seg_frames in enumerate(segments, start=1):
        segment_id = generate_segment_id()
        dest_without_ext = day_chunks_dir / segment_id
        print(f"[build_chunks] Segmento {idx}/{len(segments)} -> {dest_without_ext}.mp4")

        # Use shared library function for video creation
        frame_paths = [frame.path for frame in seg_frames]
        size, width, height = create_video_from_images(
            image_paths=frame_paths,
            output_path=dest_without_ext,
            fps=fps,
            codec="libx264",
            crf=crf,
            preset=preset,
            pix_fmt="yuv420p",
        )

        # Caminho relativo ao diretório base de dados
        base_data_dir = get_database_path().parent
        rel_path = str(dest_without_ext.with_suffix(".mp4").relative_to(base_data_dir))

        # Use DatabaseManager methods instead of direct SQL
        start_ts = seg_frames[0].ts
        end_ts = seg_frames[-1].ts
        db.insert_segment(
            segment_id=segment_id,
            date_str=date_str,
            start_ts=start_ts,
            end_ts=end_ts,
            frame_count=len(seg_frames),
            fps=fps,
            file_size_bytes=size,
            video_path=rel_path,
            width=width,
            height=height,
        )

    # Persiste todos os appsegments calculados para o dia.
    for app_id, start_ts, end_ts in appsegments:
        appsegment_id = generate_segment_id()
        db.insert_appsegment(
            appsegment_id=appsegment_id,
            date_str=date_str,
            start_ts=start_ts,
            end_ts=end_ts,
            app_id=app_id,
        )

    # Remove arquivos temporários após processamento bem-sucedido
    if cleanup:
        cleanup_temp_files(frames, day)


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
        "--no-cleanup",
        action="store_true",
        help="Não remove os arquivos temporários após processamento",
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
        cleanup=not args.no_cleanup,
    )


if __name__ == "__main__":
    main()
