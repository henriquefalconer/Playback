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
import tempfile
from datetime import datetime
from pathlib import Path

# Add parent directory to path to import lib modules
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from lib.paths import get_temp_directory, ensure_directory_exists, get_timeline_open_signal_path, create_secure_file
from lib.macos import is_screen_unavailable, get_active_display_index, get_frontmost_app_bundle_id
from lib.timestamps import generate_chunk_name
from lib.config import load_config_with_defaults


def _has_screen_recording_permission() -> bool:
    """
    Verifica se o processo tem permissão de Screen Recording tentando capturar uma screenshot de teste.
    Retorna True se bem-sucedido, False se a permissão foi negada.
    """
    try:
        # Cria um arquivo temporário para o teste
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as temp_file:
            temp_path = Path(temp_file.name)

        try:
            # Tenta capturar uma screenshot de teste
            cmd = [
                "screencapture",
                "-x",  # sem UI / som
                "-t", "png",
                str(temp_path)
            ]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)

            # Verifica se o arquivo foi criado e tem tamanho > 0
            if result.returncode == 0 and temp_path.exists() and temp_path.stat().st_size > 0:
                return True
            else:
                return False

        finally:
            # Limpa o arquivo de teste
            if temp_path.exists():
                temp_path.unlink()

    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, Exception) as e:
        print(f"[Playback] Erro ao verificar permissão: {e}")
        return False


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

    Screenshots are created with secure permissions (0o600) to prevent other
    users from accessing recorded screen data.
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

    # Set secure permissions on the screenshot (0o600 = user read/write only)
    import os
    os.chmod(temp_path, 0o600)

    # Renomeia removendo a extensão para ficar igual aos chunks existentes
    temp_path.rename(output_path)

    # Ensure final file also has secure permissions after rename
    os.chmod(output_path, 0o600)


def is_timeline_viewer_open() -> bool:
    """
    Verifica se o timeline viewer está aberto checando a existência do arquivo .timeline_open.
    Retorna True se o arquivo existe, False caso contrário.
    """
    signal_path = get_timeline_open_signal_path()
    return signal_path.exists()


def main(
    interval_seconds: int = 2,
) -> None:
    """
    Loop principal:
    - A cada `interval_seconds`, tira um screenshot e salva no diretório de temp.
    - Pausa automaticamente quando o timeline viewer está aberto.
    - Pula apps excluídos conforme configuração.
    """
    # Verifica permissão de Screen Recording antes de iniciar
    if not _has_screen_recording_permission():
        error_message = """
[Playback] ERRO: Permissão de Screen Recording não concedida.

Para conceder a permissão:
1. Abra System Settings (Preferências do Sistema)
2. Vá para Privacy & Security > Screen Recording
3. Ative a permissão para o app que está executando este script
   (pode ser Terminal, Python, ou o próprio Playback)
4. Reinicie este serviço após conceder a permissão

O serviço será encerrado agora.
"""
        print(error_message, file=sys.stderr)
        sys.exit(1)

    print("[Playback] Permissão de Screen Recording verificada com sucesso")

    temp_root = get_temp_directory()
    signal_path = get_timeline_open_signal_path()
    config = load_config_with_defaults()

    print(f"[Playback] Iniciando gravação de tela com intervalo de {interval_seconds}s...")
    print(f"[Playback] Salvando em: {temp_root}")
    print(f"[Playback] Monitorando sinal de pause em: {signal_path}")

    if config.excluded_apps:
        print(f"[Playback] Apps excluídos (modo {config.exclusion_mode}): {', '.join(config.excluded_apps)}")
    else:
        print(f"[Playback] Nenhum app excluído")

    timeline_was_open = False
    last_config_check = time.time()

    while True:
        now = datetime.now()
        print(f"[Playback] DEBUG: Iniciando ciclo de captura às {now.strftime('%H:%M:%S')}")

        # Reload config every 30 seconds to pick up changes
        if time.time() - last_config_check > 30:
            config = load_config_with_defaults()
            last_config_check = time.time()

        # Verifica se o timeline viewer está aberto
        timeline_open = is_timeline_viewer_open()

        # Log mudanças de estado do timeline viewer
        if timeline_open and not timeline_was_open:
            print(f"[Playback] Timeline viewer aberto - pausando gravação")
            timeline_was_open = True
        elif not timeline_open and timeline_was_open:
            print(f"[Playback] Timeline viewer fechado - retomando gravação")
            timeline_was_open = False

        # Se o timeline viewer está aberto, não gravamos nada neste ciclo
        if timeline_open:
            print(f"[Playback] DEBUG: Pulando captura (timeline viewer aberto), aguardando {interval_seconds}s...")
            time.sleep(interval_seconds)
            continue

        # Se a tela estiver em protetor de tela / bloqueada / desligada,
        # não gravamos nada neste ciclo.
        screen_unavailable = is_screen_unavailable()
        print(f"[Playback] DEBUG: screen_unavailable = {screen_unavailable}")

        if screen_unavailable:
            print(f"[Playback] DEBUG: Pulando captura (tela indisponível), aguardando {interval_seconds}s...")
            time.sleep(interval_seconds)
            continue

        print(f"[Playback] DEBUG: Tela disponível, prosseguindo com captura...")

        # Get frontmost app bundle ID
        app_id = get_frontmost_app_bundle_id()

        # Check if app is excluded
        if config.is_app_excluded(app_id):
            if config.exclusion_mode == "skip":
                print(f"[Playback] Pulando captura (app excluído: {app_id}), aguardando {interval_seconds}s...")
                time.sleep(interval_seconds)
                continue
            # If exclusion_mode is "invisible", we still capture but could blur or black out the content
            # For now, we just continue with normal capture (implement blurring in future if needed)

        day_dir = ensure_chunk_dir(now)

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
