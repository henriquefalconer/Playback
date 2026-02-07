#!/usr/bin/env python3
"""
Proof-of-concept de gravação de tela para o macOS.

Funciona assim:
- Em loop infinito, tira screenshots da tela atual usando o utilitário nativo `screencapture`.
- Salva os arquivos em uma estrutura de pastas do tipo:

  com.playback.Playback/temp/YYYYMM/DD/<id>

- Cada arquivo é uma imagem PNG, mas sem extensão, imitando o padrão de `com.memoryvault.MemoryVault/chunks`.

Requisitos:
- macOS (já inclui o binário `screencapture`)
- Python 3
- Permissão de "Gravação de Tela" nas Preferências do Sistema para o Terminal/Cursor.
"""

import subprocess
import time
import sys
from datetime import datetime
from pathlib import Path

# Add parent directory to path to import lib modules
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from lib.paths import get_temp_directory, ensure_directory_exists
from lib.macos import is_screen_unavailable, get_active_display_index, get_frontmost_app_bundle_id
from lib.timestamps import generate_chunk_name


def ensure_chunk_dir(now: datetime) -> Path:
    """
    Garante que a pasta temp/YYYYMM/DD exista.
    Retorna o caminho da pasta do dia.
    """
    year_month = now.strftime("%Y%m")  # ex: 202512
    day = now.strftime("%d")           # ex: 22

    day_dir = get_temp_directory() / year_month / day
    ensure_directory_exists(day_dir, mode=0o700)
    return day_dir


def capture_screen(output_path: Path) -> None:
    """
    Usa o binário nativo `screencapture` do macOS para tirar screenshot da tela.
    -x: sem som de câmera
    -t png: formato PNG
    """
    # Salvamos em um arquivo temporário com extensão .png,
    # depois renomeamos para remover a extensão (imitando o outro app).
    temp_path = output_path.with_suffix(".png")

    # Tenta descobrir qual monitor está em uso (onde está a janela em foco)
    # para capturar o DISPLAY inteiro com `screencapture -D`.
    display_index = get_active_display_index()

    cmd = [
        "screencapture",
        "-x",        # sem UI / som
        "-t",
        "png",       # formato
    ]
    if display_index is not None:
        print(f"[Playback] Usando screencapture -D {display_index} (monitor em uso)")
        cmd.extend(["-D", str(display_index)])

    cmd.append(str(temp_path))

    subprocess.run(cmd, check=True)

    # Renomeia removendo a extensão para ficar igual aos chunks existentes
    temp_path.rename(output_path)


def main(
    interval_seconds: int = 2,
) -> None:
    """
    Loop principal:
    - A cada `interval_seconds`, tira um screenshot e salva no diretório de temp.
    """
    temp_root = get_temp_directory()
    print(f"[Playback] Iniciando gravação de tela com intervalo de {interval_seconds}s...")
    print(f"[Playback] Salvando em: {temp_root}")

    while True:
        now = datetime.now()
        print(f"[Playback] DEBUG: Iniciando ciclo de captura às {now.strftime('%H:%M:%S')}")

        # Se a tela estiver em protetor de tela / bloqueada / desligada,
        # não gravamos nada neste ciclo.
        screen_unavailable = is_screen_unavailable()
        print(f"[Playback] DEBUG: screen_unavailable = {screen_unavailable}")

        if screen_unavailable:
            print(f"[Playback] DEBUG: Pulando captura (tela indisponível), aguardando {interval_seconds}s...")
            time.sleep(interval_seconds)
            continue

        print(f"[Playback] DEBUG: Tela disponível, prosseguindo com captura...")
        day_dir = ensure_chunk_dir(now)

        # Get frontmost app bundle ID
        app_id = get_frontmost_app_bundle_id()

        # Generate chunk name with timestamp and app ID
        chunk_name = generate_chunk_name(now, app_id)
        chunk_path = day_dir / chunk_name

        try:
            capture_screen(chunk_path)
            print(f"[Playback] Captura salva em: {chunk_path}")
        except subprocess.CalledProcessError as e:
            print(f"[Playback] ERRO ao capturar tela: {e}")

        time.sleep(interval_seconds)


if __name__ == "__main__":
    # Para PoC, intervalo padrão de 2s.
    # Você pode mudar para 1–5s se quiser algo mais frequente.
    main(interval_seconds=2)
